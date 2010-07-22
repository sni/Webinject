#!/usr/bin/perl -w

#    Copyright 2004-2006 Corey Goldberg (corey@goldb.org)
#
#    This file is part of WebInject.
#
#    WebInject is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    WebInject is distributed in the hope that it will be useful,
#    but without any warranty; without even the implied warranty of
#    merchantability or fitness for a particular purpose.  See the
#    GNU General Public License for more details.


our $version="1.41";

use strict;
use LWP;
use HTTP::Request::Common;
use HTTP::Cookies;
use XML::Simple;
use Time::HiRes 'time','sleep';
use Getopt::Long;
use Crypt::SSLeay;  #for SSL/HTTPS (you may comment this out if you don't need it)
use XML::Parser;  #for web services verification (you may comment this out if aren't doing XML verifications for web services)
use Error qw(:try);  #for web services verification (you may comment this out if aren't doing XML verifications for web services)
#use Data::Dumper;  #uncomment to dump hashes for debugging   


$| = 1; #don't buffer output to STDOUT


our ($timestamp, $dirname);
our (%parsedresult);
our ($useragent, $request, $response);
our ($gui, $monitorenabledchkbx, $latency);
our ($cookie_jar, @httpauth);
our ($xnode, $graphtype, $plotclear, $stop, $nooutput);
our ($runcount, $totalruncount, $casepassedcount, $casefailedcount, $passedcount, $failedcount);
our ($totalresponse, $avgresponse, $maxresponse, $minresponse);
our (@casefilelist, $currentcasefile, $casecount, $isfailure);
our (%case, $verifylater, $verifylaterneg);
our (%config);
our ($currentdatetime, $totalruntime, $starttimer, $endtimer);
our ($opt_configfile, $opt_version, $opt_output);
our ($reporttype, $returnmessage, %exit_codes);


if (($0 =~ /webinject.pl/) or ($0 =~ /webinject.exe/)) {  #set flag so we know if it is running standalone or from webinjectgui
    $gui = 0; 
    engine();
}
else {
    $gui = 1;
    getdirname();  #get the directory webinject engine is running from
    whackoldfiles(); #delete files leftover from previous run (do this here so they are whacked on startup when running from gui)
}



#------------------------------------------------------------------
sub engine {   #wrap the whole engine in a subroutine so it can be integrated with the gui 
      
    our ($startruntimer, $endruntimer, $repeat);
    our ($curgraphtype);
    our ($casefilecheck, $testnum, $xmltestcases);

    # undef local values
    map { $case{$_} = undef } qw/method description1 description2 sleep/;
        
    if ($gui == 1) { gui_initial(); }
        
    getdirname();  #get the directory webinject engine is running from
        
    getoptions();  #get command line options
        
    whackoldfiles();  #delete files leftover from previous run (do this here so they are whacked each run)
        
    #contsruct objects
    $useragent = LWP::UserAgent->new;
    $cookie_jar = HTTP::Cookies->new;
    $useragent->agent('WebInject');  #http useragent that will show up in webserver logs
    $useragent->max_redirect('0');  #don't follow redirects for GET's (POST's already don't follow, by default)
        
        
    if ($gui != 1){   
        $graphtype = 'lines'; #default to line graph if not in GUI
        $config{standaloneplot} = 'off'; #initialize so we don't get warnings when <standaloneplot> is not set in config         
    }
        
    processcasefile();
        
    #add proxy support if it is set in config.xml
    if ($config{proxy}) {
        $useragent->proxy(['http', 'https'], "$config{proxy}")
    } 
        
    #add http basic authentication support
    #corresponds to:
    #$useragent->credentials('servername:portnumber', 'realm-name', 'username' => 'password');
    if (@httpauth) {
        #add the credentials to the user agent here. The foreach gives the reference to the tuple ($elem), and we 
        #deref $elem to get the array elements.  
        my $elem;
        foreach $elem(@httpauth) {
            #print "adding credential: $elem->[0]:$elem->[1], $elem->[2], $elem->[3] => $elem->[4]\n";
            $useragent->credentials("$elem->[0]:$elem->[1]", "$elem->[2]", "$elem->[3]" => "$elem->[4]");
        }
    }
        
    #change response delay timeout in seconds if it is set in config.xml      
    if ($config{timeout}) {
        $useragent->timeout("$config{timeout}");  #default LWP timeout is 180 secs.
    }
        
    #open file handles
    unless ($reporttype) {  #we suppress most logging when running in a plugin mode
        if ($opt_output) {  #use output location if it is passed from the command line
            open(HTTPLOGFILE, ">$opt_output"."http.log") or die "\nERROR: Failed to open http.log file\n\n";   
            open(RESULTS, ">$opt_output"."results.html") or die "\nERROR: Failed to open results.html file\n\n";    
            open(RESULTSXML, ">$opt_output"."results.xml") or die "\nERROR: Failed to open results.xml file\n\n";
        }
        else {
            open(HTTPLOGFILE, ">$dirname"."http.log") or die "\nERROR: Failed to open http.log file\n\n";   
            open(RESULTS, ">$dirname"."results.html") or die "\nERROR: Failed to open results.html file\n\n";    
            open(RESULTSXML, ">$dirname"."results.xml") or die "\nERROR: Failed to open results.xml file\n\n";
        }
    }
        
    unless ($reporttype) {  #we suppress most logging when running in a plugin mode 
        print RESULTSXML qq|<results>\n\n|;  #write initial xml tag
        writeinitialhtml();  #write opening tags for results file
    }
               
    unless ($xnode or $nooutput) { #skip regular STDOUT output if using an XPath or $nooutput is set 
        writeinitialstdout();  #write opening tags for STDOUT. 
    }
        
    if ($gui == 1){ $curgraphtype = $graphtype; }  #set the initial value so we know if the user changes the graph setting from the gui
        
    gnuplotcfg(); #create the gnuplot config file
        
        
    $totalruncount = 0;
    $casepassedcount = 0;
    $casefailedcount = 0;
    $passedcount = 0;
    $failedcount = 0;
    $totalresponse = 0;
    $avgresponse = 0;
    $maxresponse = 0;
    $minresponse = 10000000; #set to large value so first minresponse will be less
    $stop = 'no';
    $plotclear = 'no';
        
        
    $currentdatetime = localtime time;  #get current date and time for results report
    $startruntimer = time();  #timer for entire test run
        
        
    foreach (@casefilelist) { #process test case files named in config
        
        $currentcasefile = $_;
        #print "\n$currentcasefile\n\n";
            
        $casefilecheck = ' ';
            
        if ($gui == 1){ gui_processing_msg(); }
            
        convtestcases();
            
        fixsinglecase();
          
        $xmltestcases = XMLin("$dirname"."$currentcasefile".".$$".".tmp", VarAttr => 'varname'); #slurp test case file to parse (and specify variables tag)
        #print Dumper($xmltestcases);  #for debug, dump hash of xml   
        #print keys %{$configfile};  #for debug, print keys from dereferenced hash
            
        #delete the temp file as soon as we are done reading it    
        if (-e "$dirname"."$currentcasefile".".$$".".tmp") { unlink "$dirname"."$currentcasefile".".$$".".tmp"; }        
            
            
        $repeat = $xmltestcases->{repeat};  #grab the number of times to iterate test case file
        unless ($repeat) { $repeat = 1; }  #set to 1 in case it is not defined in test case file               
            
            
        foreach (1 .. $repeat) {
                
            $runcount = 0;
                
            foreach (sort {$a<=>$b} keys %{$xmltestcases->{case}}) {  #process cases in sorted order
                    
                $testnum = $_;
                    
                if ($xnode) {  #if an XPath Node is defined, only process the single Node 
                    $testnum = $xnode; 
                }
                 
                $isfailure = 0;
                    
                if ($gui == 1){
                    unless ($monitorenabledchkbx eq 'monitor_off') {  #don't do this if monitor is disabled in gui
                        if ("$curgraphtype" ne "$graphtype") {  #check to see if the user changed the graph setting
                            gnuplotcfg();  #create the gnuplot config file since graph setting changed
                            $curgraphtype = $graphtype;
                        }
                    }
                }
                    
                $timestamp = time();  #used to replace parsed {timestamp} with real timestamp value
                    
                if ($case{verifypositivenext}) { $verifylater = $case{verifypositivenext}; }  #grab $case{verifypositivenext} string from previous test case (if it exists)
                if ($case{verifynegativenext}) { $verifylaterneg = $case{verifynegativenext}; }  #grab $case{verifynegativenext} string from previous test case (if it exists)
                    
                # populate variables with values from testcase file, do substitutions, and revert converted values back
		for (qw/method description1 description2 url postbody posttype addheader
			verifypositive verifypositive1 verifypositive2 verifypositive3
			verifynegative verifynegative1 verifynegative2 verifynegative3
			parseresponse parseresponse1 parseresponse2 parseresponse3 parseresponse4 parseresponse5
			verifyresponsecode logrequest logresponse sleep errormessage
			verifypositivenext verifynegativenext/) {
		  $case{$_} = $xmltestcases->{case}->{$testnum}->{$_};
		  if ($case{$_}) { convertbackxml($case{$_}); }
		}

		if ($gui == 1){ gui_tc_descript(); }

                if ($case{description1} and $case{description1} =~ /dummy test case/) {  #if we hit a dummy record, skip it
                    next;
                }
                    
                unless ($reporttype) {  #we suppress most logging when running in a plugin mode 
                    print RESULTS qq|<b>Test:  $currentcasefile - $testnum </b><br />\n|;
                }
                    
                unless ($nooutput) { #skip regular STDOUT output 
                    print STDOUT qq|Test:  $currentcasefile - $testnum \n|;
                }
                    
                unless ($reporttype) {  #we suppress most logging when running in a plugin mode     
                    unless ($casefilecheck eq $currentcasefile) {
                        unless ($currentcasefile eq $casefilelist[0]) {  #if this is the first test case file, skip printing the closing tag for the previous one
                            print RESULTSXML qq|    </testcases>\n\n|;
                        }
                        print RESULTSXML qq|    <testcases file="$currentcasefile">\n\n|;
                    }
                    print RESULTSXML qq|        <testcase id="$testnum">\n|;
                }
                    
		for (qw/description1 description2/) {
                    next unless defined $case{$_};
                    unless ($reporttype) {  #we suppress most logging when running in a plugin mode 
                        print RESULTS qq|$case{$_} <br />\n|; 
                        unless ($nooutput) { #skip regular STDOUT output 
                            print STDOUT qq|$case{$_} \n|;
                        }
                        print RESULTSXML qq|            <$_>$case{$_}</$_>\n|;
                    }
	        }                    
                    
                unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                    print RESULTS qq|<br />\n|;
                }

		for (qw/verifypositive verifypositive1 verifypositive2 verifypositive3
			verifynegative verifynegative1 verifynegative2 verifynegative3/) {
                    my $negative = $_ =~ /negative/ ? "Negative" : "";
                    if ($case{$_}) {
                        unless ($reporttype) {  #we suppress most logging when running in a plugin mode 
                            print RESULTS qq|Verify $negative: "$case{$_}" <br />\n|;
                            unless ($nooutput) { #skip regular STDOUT output 
                                print STDOUT qq|Verify $negative: "$case{$_}" \n|;
                            }
                            print RESULTSXML qq|            <$_>$case{$_}</$_>\n|;
                        }
                    }
                }                    

                if ($case{verifypositivenext}) { 
                    unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                        print RESULTS qq|Verify On Next Case: "$case{verifypositivenext}" <br />\n|;
                        unless ($nooutput) { #skip regular STDOUT output  
                            print STDOUT qq|Verify On Next Case: "$case{verifypositivenext}" \n|;
                        }
                        print RESULTSXML qq|            <verifypositivenext>$case{verifypositivenext}</verifypositivenext>\n|;
                    }
                }
                    
                if ($case{verifynegativenext}) { 
                    unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                        print RESULTS qq|Verify Negative On Next Case: "$case{verifynegativenext}" <br />\n|;
                        unless ($nooutput) { #skip regular STDOUT output  
                            print STDOUT qq|Verify Negative On Next Case: "$case{verifynegativenext}" \n|;
                        }
                        print RESULTSXML qq|            <verifynegativenext>$case{verifynegativenext}</verifynegativenext>\n|;
                    }
                }
                    
                if ($case{verifyresponsecode}) {
                    unless ($reporttype) {  #we suppress most logging when running in a plugin mode 
                        print RESULTS qq|Verify Response Code: "$case{verifyresponsecode}" <br />\n|;
                        unless ($nooutput) { #skip regular STDOUT output 
                            print STDOUT qq|Verify Response Code: "$case{verifyresponsecode}" \n|;
                        }
                        print RESULTSXML qq|            <verifyresponsecode>$case{verifyresponsecode}</verifyresponsecode>\n|;
                    }
                }
                    
                    
                if ($case{method}) {
                    if ($case{method} eq "get") { httpget(); }
                    elsif ($case{method} eq "post") { httppost(); }
                    else { print STDERR qq|ERROR: bad HTTP Request Method Type, you must use "get" or "post"\n|; }
                }
                else {   
                    httpget();  #use "get" if no method is specified  
                }  
                    
                    
                verify();  #verify result from http response
                    
                httplog();  #write to http.log file
                    
                plotlog($latency);  #send perf data to log file for plotting
                    
                plotit();  #call the external plotter to create a graph
                 
                if ($gui == 1) { 
                    gui_updatemontab();  #update monitor with the newly rendered plot graph 
                }   
                    
                    
                parseresponse();  #grab string from response to send later
                    
                    
                if ($isfailure > 0) {  #if any verification fails, test case is considered a failure
                    unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                        print RESULTSXML qq|            <success>false</success>\n|;
                    }
                    if ($case{errormessage}) { #Add defined error message to the output 
                        unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                            print RESULTS qq|<b><span class="fail">TEST CASE FAILED : $case{errormessage}</span></b><br />\n|;
                            print RESULTSXML qq|            <result-message>$case{errormessage}</result-message>\n|;
                        }
                        unless ($nooutput) { #skip regular STDOUT output 
                            print STDOUT qq|TEST CASE FAILED : $case{errormessage}\n|;
                        }
                    }
                    else { #print regular error output
                        unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                            print RESULTS qq|<b><span class="fail">TEST CASE FAILED</span></b><br />\n|;
                            print RESULTSXML qq|            <result-message>TEST CASE FAILED</result-message>\n|;
                        }
                        unless ($nooutput) { #skip regular STDOUT output 
                            print STDOUT qq|TEST CASE FAILED\n|;
                        }
                    }    
                    unless ($returnmessage) {  #(used for plugin compatibility) if it's the first error message, set it to variable
                        if ($case{errormessage}) { 
                            $returnmessage = $case{errormessage}; 
                        }
                        else { 
                            $returnmessage = "Test case number $testnum failed"; 
                        }
                        #print "\nReturn Message : $returnmessage\n"
                    }
                    if ($gui == 1){ 
                        gui_status_failed();
                    }
                    $casefailedcount++;
                }
                else {
                    unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                        print RESULTS qq|<b><span class="pass">TEST CASE PASSED</span></b><br />\n|;
                    }
                    unless ($nooutput) { #skip regular STDOUT output 
                        print STDOUT qq|TEST CASE PASSED \n|;
                    }
                    unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                        print RESULTSXML qq|            <success>true</success>\n|;
                        print RESULTSXML qq|            <result-message>TEST CASE PASSED</result-message>\n|;
                    }
                    if ($gui == 1){
                        gui_status_passed(); 
                    }
                    $casepassedcount++;
                }
                    
                    
                unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                    print RESULTS qq|Response Time = $latency sec <br />\n|;
                }
                    
                if ($gui == 1) { gui_timer_output(); } 
                    
                unless ($nooutput) { #skip regular STDOUT output 
                    print STDOUT qq|Response Time = $latency sec \n|;
                }
                    
                unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                    print RESULTSXML qq|            <responsetime>$latency</responsetime>\n|;
                    print RESULTSXML qq|        </testcase>\n\n|;
                    print RESULTS qq|<br />\n------------------------------------------------------- <br />\n\n|;
                }
                    
                unless ($xnode or $nooutput) { #skip regular STDOUT output if using an XPath or $nooutput is set   
                    print STDOUT qq|------------------------------------------------------- \n|;
                }
                    
                $casefilecheck = $currentcasefile;  #set this so <testcases> xml is only closed after each file is done processing
                   
                $endruntimer = time();
                $totalruntime = (int(1000 * ($endruntimer - $startruntimer)) / 1000);  #elapsed time rounded to thousandths 
                    
                $runcount++;    
                $totalruncount++;
                    
                if ($gui == 1) { 
                    gui_statusbar();  #update the statusbar
                }   
                    
                if ($latency > $maxresponse) { $maxresponse = $latency; }  #set max response time
                if ($latency < $minresponse) { $minresponse = $latency; }  #set min response time
                $totalresponse = ($totalresponse + $latency);  #keep total of response times for calculating avg 
                $avgresponse = (int(1000 * ($totalresponse / $totalruncount)) / 1000);  #avg response rounded to thousandths
                    
                if ($gui == 1) { gui_updatemonstats(); }  #update timers and counts in monitor tab   
                    
                #break from sub if user presses stop button in gui    
                if ($stop eq 'yes') {
                    finaltasks();
                    $stop = 'no';
                    return;  #break from sub
                }
                    
                if ($case{sleep}) {  #if a sleep value is set in the test case, sleep that amount
                    sleep($case{sleep})
                }
                    
                if ($xnode) {  #if an XPath Node is defined, only process the single Node 
                    last;
                }
                    
            }
                
            $testnum = 1;  #reset testcase counter so it will reprocess test case file if repeat is set
        }
    }
        
    finaltasks();  #do return/cleanup tasks
        
} #end engine subroutine



#------------------------------------------------------------------
#  SUBROUTINES
#------------------------------------------------------------------
sub writeinitialhtml {  #write opening tags for results file
        
    print RESULTS 
qq|<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">

<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <title>WebInject Test Results</title>
    <meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />
    <style type="text/css">
        body {
            background-color: #F5F5F5;
            color: #000000;
            font-family: Verdana, Arial, Helvetica, sans-serif; 
            font-size: 10px;
        }
        .pass { 
            color: green; 
        }
        .fail { 
            color: red;
        }
    </style>
</head>
<body>
<hr />
-------------------------------------------------------<br />
|; 
}
#------------------------------------------------------------------
sub writeinitialstdout {  #write initial text for STDOUT
        
    print STDOUT 
qq|
Starting WebInject Engine...

-------------------------------------------------------
|; 
}
#------------------------------------------------------------------
sub writefinalhtml {  #write summary and closing tags for results file
        
    print RESULTS
qq|    
<br /><hr /><br />
<b>
Start Time: $currentdatetime <br />
Total Run Time: $totalruntime seconds <br />
<br />
Test Cases Run: $totalruncount <br />
Test Cases Passed: $casepassedcount <br />
Test Cases Failed: $casefailedcount <br />
Verifications Passed: $passedcount <br />
Verifications Failed: $failedcount <br />
<br />
Average Response Time: $avgresponse seconds <br />
Max Response Time: $maxresponse seconds <br />
Min Response Time: $minresponse seconds <br />
</b>
<br />

</body>
</html>
|; 
}
#------------------------------------------------------------------
sub writefinalxml {  #write summary and closing tags for XML results file
        
    print RESULTSXML
qq|    
    </testcases>

    <test-summary>
        <start-time>$currentdatetime</start-time>
        <total-run-time>$totalruntime</total-run-time>
        <test-cases-run>$totalruncount</test-cases-run>
        <test-cases-passed>$casepassedcount</test-cases-passed>
        <test-cases-failed>$casefailedcount</test-cases-failed>
        <verifications-passed>$passedcount</verifications-passed>
        <verifications-failed>$failedcount</verifications-failed>
        <average-response-time>$avgresponse</average-response-time>
        <max-response-time>$maxresponse</max-response-time>
        <min-response-time>$minresponse</min-response-time>
    </test-summary>

</results>
|; 
}
#------------------------------------------------------------------
sub writefinalstdout {  #write summary and closing text for STDOUT
        
    print STDOUT
qq|    
Start Time: $currentdatetime
Total Run Time: $totalruntime seconds

Test Cases Run: $totalruncount
Test Cases Passed: $casepassedcount
Test Cases Failed: $casefailedcount 
Verifications Passed: $passedcount
Verifications Failed: $failedcount

|; 
}
#------------------------------------------------------------------
sub httpget {  #send http request and read response
        
    $request = new HTTP::Request('GET',"$case{url}");
    
    if ($case{addheader}) {  #add an additional HTTP Header if specified
        my @addheaders = split(/\|/, $case{addheader});  #can add multiple headers with a pipe delimiter
        foreach (@addheaders) {
            $_ =~ m~(.*): (.*)~;
            $request->header($1 => $2);  #using HTTP::Headers Class
        }
        $case{addheader} = '';
    }
    
    $cookie_jar->add_cookie_header($request);
    #print $request->as_string; print "\n\n";
        
    $starttimer = time();
    $response = $useragent->request($request);
    $endtimer = time();
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  #elapsed time rounded to thousandths 
    #print $response->as_string; print "\n\n";
        
    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n";
}
#------------------------------------------------------------------
sub httppost {  #post request based on specified encoding
        
    if ($case{posttype}) {
	if ($case{posttype} =~ m~application/x-www-form-urlencoded~) { httppost_form_urlencoded(); }
        elsif ($case{posttype} =~ m~multipart/form-data~) { httppost_form_data(); }
        elsif (($case{posttype} =~ m~text/xml~) or ($case{posttype} =~ m~application/soap+xml~)) { httppost_xml(); }
        else { print STDERR qq|ERROR: Bad Form Encoding Type, I only accept "application/x-www-form-urlencoded", "multipart/form-data", "text/xml", "application/soap+xml" \n|; }
    }
    else {   
        $case{posttype} = 'application/x-www-form-urlencoded';
        httppost_form_urlencoded();  #use "x-www-form-urlencoded" if no encoding is specified  
    }
}
#------------------------------------------------------------------
sub httppost_form_urlencoded {  #send application/x-www-form-urlencoded HTTP request and read response
        
    $request = new HTTP::Request('POST',"$case{url}");
    $request->content_type("$case{posttype}");
    $request->content("$case{postbody}");
    
    if ($case{addheader}) {  #add an additional HTTP Header if specified
        my @addheaders = split(/\|/, $case{addheader});  #can add multiple headers with a pipe delimiter
        foreach (@addheaders) {
            $_ =~ m~(.*): (.*)~;
            $request->header($1 => $2);  #using HTTP::Headers Class
        }
        $case{addheader} = '';
    }
    
    $cookie_jar->add_cookie_header($request);
    #print $request->as_string; print "\n\n";
    $starttimer = time();
    $response = $useragent->request($request);
    $endtimer = time();
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  #elapsed time rounded to thousandths 
    #print $response->as_string; print "\n\n";
        
    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n";
}
#------------------------------------------------------------------
sub httppost_xml{  #send text/xml HTTP request and read response 
    
    #read the xml file specified in the testcase
    $case{postbody} =~ m~file=>(.*)~i;
    open(XMLBODY, "$dirname"."$1") or die "\nError: Failed to open text/xml file\n\n";  #open file handle   
    my @xmlbody = <XMLBODY>;  #read the file into an array   
    close(XMLBODY);
        
    $request = new HTTP::Request('POST', "$case{url}"); 
    $request->content_type("$case{posttype}");
    $request->content(join(" ", @xmlbody));  #load the contents of the file into the request body 
    
    if ($case{addheader}) {  #add an additional HTTP Header if specified
        my @addheaders = split(/\|/, $case{addheader});  #can add multiple headers with a pipe delimiter
        foreach (@addheaders) {
            $_ =~ m~(.*): (.*)~;
            $request->header($1 => $2);  #using HTTP::Headers Class
        }
        $case{addheader} = '';
    }
    
    $cookie_jar->add_cookie_header($request);
    #print $request->as_string; print "\n\n";    
    $starttimer = time(); 
    $response = $useragent->request($request); 
    $endtimer = time(); 
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  #elapsed time rounded to thousandths 
    #print $response->as_string; print "\n\n";    

    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n";


    my $xmlparser = new XML::Parser;
    try {  #see if the XML parses properly
        $xmlparser->parse($response->content);
        #print "good xml\n";
        unless ($reporttype) {  #we suppress most logging when running in a plugin mode
            print RESULTS qq|<span class="pass">Passed XML Parser (content is well-formed)</span><br />\n|;
            print RESULTSXML qq|            <verifyxml-success>true</verifyxml-success>\n|;
        }
        unless ($nooutput) { #skip regular STDOUT output 
            print STDOUT "Passed XML Parser (content is well-formed) \n";
        }
        $passedcount++;
        return; #exit try block
    }
    catch Error with {
        my $ex = shift;  #get the exception object
        #print "bad xml\n";
        unless ($reporttype) {  #we suppress most logging when running in a plugin mode
            print RESULTS qq|<span class="fail">Failed XML Parser: $ex</span><br />\n|;
            print RESULTSXML qq|            <verifyxml-success>false</verifyxml-success>\n|;
        }
        unless ($nooutput) { #skip regular STDOUT output  
            print STDOUT "Failed XML Parser: $ex \n";         
        }
        $failedcount++;
        $isfailure++;
    };  # <-- remember the semicolon

}
#------------------------------------------------------------------
sub httppost_form_data {  #send multipart/form-data HTTP request and read response
	
    my %myContent_;
    eval "\%myContent_ = $case{postbody}";
    $request = POST "$case{url}",
               Content_Type => "$case{posttype}",
               Content => \%myContent_;
    $cookie_jar->add_cookie_header($request);
    #print $request->as_string; print "\n\n";
    
    if ($case{addheader}) {  #add an additional HTTP Header if specified
        my @addheaders = split(/\|/, $case{addheader});  #can add multiple headers with a pipe delimiter
        foreach (@addheaders) {
            $_ =~ m~(.*): (.*)~;
            $request->header($1 => $2);  #using HTTP::Headers Class
        }
        $case{addheader} = '';
    }
    
    $starttimer = time();
    $response = $useragent->request($request);
    $endtimer = time();
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  #elapsed time rounded to thousandths 
    #print $response->as_string; print "\n\n";
        
    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n";
}
#------------------------------------------------------------------
sub verify {  #do verification of http response and print status to HTML/XML/STDOUT/UI

    for (qw/verifypositive verifypositive1 verifypositive2 verifypositive3/) {
    
        if ($case{$_}) {
            if ($response->as_string() =~ m~$case{$_}~si) {  #verify existence of string in response
                unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                    print RESULTS qq|<span class="pass">Passed Positive Verification</span><br />\n|;
                    print RESULTSXML qq|            <$_-success>true</$_-success>\n|;
                }
                unless ($nooutput) { #skip regular STDOUT output 
                    print STDOUT "Passed Positive Verification \n";
                }
                $passedcount++;
            }
            else {
                unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                    print RESULTS qq|<span class="fail">Failed Positive Verification</span><br />\n|;
                    print RESULTSXML qq|            <$_-success>false</$_-success>\n|;
                }
                unless ($nooutput) { #skip regular STDOUT output  
                    print STDOUT "Failed Positive Verification \n";         
                }
                $failedcount++;
                $isfailure++;
            }
        }
    }    
    
    for (qw/verifynegative verifynegative1 verifynegative2 verifynegative3/) {        
        
        if ($case{$_}) {
            if ($response->as_string() =~ m~$case{$_}~si) {  #verify existence of string in response
                unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                    print RESULTS qq|<span class="fail">Failed Negative Verification</span><br />\n|;
                    print RESULTSXML qq|            <$_-success>false</$_-success>\n|;
                }
                unless ($nooutput) { #skip regular STDOUT output 
                    print STDOUT "Failed Negative Verification \n";            
                }
                $failedcount++;
                $isfailure++;
            }
            else {
                unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                    print RESULTS qq|<span class="pass">Passed Negative Verification</span><br />\n|;
                    print RESULTSXML qq|            <$_-success>true</$_-success>\n|;
                }
                unless ($nooutput) { #skip regular STDOUT output 
                    print STDOUT "Passed Negative Verification \n";
                }
                $passedcount++;                
            }
        }
    }
       
    if ($verifylater) {
        if ($response->as_string() =~ m~$verifylater~si) {  #verify existence of string in response
            unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                print RESULTS qq|<span class="pass">Passed Positive Verification (verification set in previous test case)</span><br />\n|;
                print RESULTSXML qq|            <verifypositivenext-success>true</verifypositivenext-success>\n|;
            }
            unless ($xnode or $nooutput) { #skip regular STDOUT output if using an XPath or $nooutput is set 
                print STDOUT "Passed Positive Verification (verification set in previous test case) \n";
            }
            $passedcount++;
        }
        else {
            unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                print RESULTS qq|<span class="fail">Failed Positive Verification (verification set in previous test case)</span><br />\n|;
                print RESULTSXML qq|            <verifypositivenext-success>false</verifypositivenext-success>\n|;
            }
            unless ($xnode or $nooutput) { #skip regular STDOUT output if using an XPath or $nooutput is set 
                print STDOUT "Failed Positive Verification (verification set in previous test case) \n";            
            }
            $failedcount++;
            $isfailure++;            
        }        
        $verifylater = '';  #set to null after verification
    }
        
        
        
    if ($verifylaterneg) {
        if ($response->as_string() =~ m~$verifylaterneg~si) {  #verify existence of string in response

            unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                print RESULTS qq|<span class="fail">Failed Negative Verification (negative verification set in previous test case)</span><br />\n|;
                print RESULTSXML qq|            <verifynegativenext-success>false</verifynegativenext-success>\n|;
            }
            unless ($xnode or $nooutput) { #skip regular STDOUT output if using an XPath or $nooutput is set  
                print STDOUT "Failed Negative Verification (negative verification set in previous test case) \n";     
            }
            $failedcount++;
            $isfailure++;
        }
        else {
            unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                print RESULTS qq|<span class="pass">Passed Negative Verification (negative verification set in previous test case)</span><br />\n|;
                print RESULTSXML qq|            <verifynegativenext-success>true</verifynegativenext-success>\n|;
            }
            unless ($xnode or $nooutput) { #skip regular STDOUT output if using an XPath or $nooutput is set 
                print STDOUT "Passed Negative Verification (negative verification set in previous test case) \n";
            }
            $passedcount++;                   
        }
        $verifylaterneg = '';  #set to null after verification
    }
        
     
     
    if ($case{verifyresponsecode}) {
        if ($case{verifyresponsecode} == $response->code()) { #verify returned HTTP response code matches verifyresponsecode set in test case
            unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                print RESULTS qq|<span class="pass">Passed HTTP Response Code Verification </span><br />\n|; 
                print RESULTSXML qq|            <verifyresponsecode-success>true</verifyresponsecode-success>\n|;
                print RESULTSXML qq|            <verifyresponsecode-message>Passed HTTP Response Code Verification</verifyresponsecode-message>\n|;
            }
            unless ($nooutput) { #skip regular STDOUT output 
                print STDOUT qq|Passed HTTP Response Code Verification \n|; 
            }
            $passedcount++;         
            }
        else {
            unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                print RESULTS qq|<span class="fail">Failed HTTP Response Code Verification (received | . $response->code() .  qq|, expecting $case{verifyresponsecode})</span><br />\n|;
                print RESULTSXML qq|            <verifyresponsecode-success>false</verifyresponsecode-success>\n|;
                print RESULTSXML qq|            <verifyresponsecode-message>Failed HTTP Response Code Verification (received | . $response->code() .  qq|, expecting $case{verifyresponsecode})</verifyresponsecode-message>\n|;
            }
            unless ($nooutput) { #skip regular STDOUT output 
                print STDOUT qq|Failed HTTP Response Code Verification (received | . $response->code() .  qq|, expecting $case{verifyresponsecode}) \n|;
            }
            $failedcount++;
            $isfailure++;
        }
    }
    else { #verify http response code is in the 100-399 range
        if ($response->as_string() =~ /HTTP\/1.(0|1) (1|2|3)/i) {  #verify existance of string in response
            unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                print RESULTS qq|<span class="pass">Passed HTTP Response Code Verification (not in error range)</span><br />\n|; 
                print RESULTSXML qq|            <verifyresponsecode-success>true</verifyresponsecode-success>\n|;
                print RESULTSXML qq|            <verifyresponsecode-message>Passed HTTP Response Code Verification (not in error range)</verifyresponsecode-message>\n|;
            }
            unless ($nooutput) { #skip regular STDOUT output 
                print STDOUT qq|Passed HTTP Response Code Verification (not in error range) \n|; 
            }
            #succesful response codes: 100-399
            $passedcount++;         
        }
        else {
            $response->as_string() =~ /(HTTP\/1.)(.*)/i;
            if ($1) {  #this is true if an HTTP response returned 
                unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                    print RESULTS qq|<span class="fail">Failed HTTP Response Code Verification ($1$2)</span><br />\n|; #($1$2) is HTTP response code
                    print RESULTSXML qq|            <verifyresponsecode-success>false</verifyresponsecode-success>\n|;
                    print RESULTSXML qq|            <verifyresponsecode-message>Failed HTTP Response Code Verification ($1$2)</verifyresponsecode-message>\n|;
                }
                unless ($nooutput) { #skip regular STDOUT output 
                    print STDOUT "Failed HTTP Response Code Verification ($1$2) \n"; #($1$2) is HTTP response code   
                }
            }
            else {  #no HTTP response returned.. could be error in connection, bad hostname/address, or can not connect to web server
                unless ($reporttype) {  #we suppress most logging when running in a plugin mode
                    print RESULTS qq|<span class="fail">Failed - No Response</span><br />\n|; #($1$2) is HTTP response code
                    print RESULTSXML qq|            <verifyresponsecode-success>false</verifyresponsecode-success>\n|;
                    print RESULTSXML qq|            <verifyresponsecode-message>Failed - No Response</verifyresponsecode-message>\n|;
                }
                unless ($nooutput) { #skip regular STDOUT output  
                    print STDOUT "Failed - No Response \n"; #($1$2) is HTTP response code   
                }
            }
            $failedcount++;
            $isfailure++;
        }
    }        
}
#------------------------------------------------------------------
sub parseresponse {  #parse values from responses for use in future request (for session id's, dynamic URL rewriting, etc)
        
    our ($resptoparse, @parseargs);
    our ($leftboundary, $rightboundary, $escape);
     

    for (qw/parseresponse parseresponse1 parseresponse2 parseresponse3 parseresponse4 parseresponse5/) {

        next unless $case{$_};

        @parseargs = split(/\|/, $case{$_});
            
        $leftboundary = $parseargs[0]; $rightboundary = $parseargs[1]; $escape = $parseargs[2];
            
        $resptoparse = $response->as_string;
        if ($resptoparse =~ m~$leftboundary(.*?)$rightboundary~s) {
            $parsedresult{$_} = $1; 
        }
            
        if ($escape) {
            if ($escape eq 'escape') {
                $parsedresult{$_} = url_escape($parsedresult{$_});
            }
        }
        #print "\n\nParsed String: $parsedresult{$_}\n\n";
    }

        
}
#------------------------------------------------------------------
sub processcasefile {  #get test case files to run (from command line or config file) and evaluate constants
                       #parse config file and grab values it sets 
        
    my @configfile;
    my $configexists = 0;
    my $comment_mode;
    my $firstparse;
    my $filename;
    my $xpath;
    my $setuseragent;
        
    undef @casefilelist; #empty the array of test case filenames
    undef @configfile;
        
    #process the config file
    if ($opt_configfile) {  #if -c option was set on command line, use specified config file
        open(CONFIG, "$dirname"."$opt_configfile") or die "\nERROR: Failed to open $opt_configfile file\n\n";
        $configexists = 1;  #flag we are going to use a config file
    }
    elsif (-e "$dirname"."config.xml") {  #if config.xml exists, read it
        open(CONFIG, "$dirname"."config.xml") or die "\nERROR: Failed to open config.xml file\n\n";
        $configexists = 1;  #flag we are going to use a config file
    } 
        
    if ($configexists) {  #if we have a config file, use it  
            
        my @precomment = <CONFIG>;  #read the config file into an array
            
        #remove any commented blocks from config file
         foreach (@precomment) {
            unless (m~<comment>.*</comment>~) {  #single line comment 
                #multi-line comments
                if (/<comment>/) {   
                    $comment_mode = 1;
                } 
                elsif (m~</comment>~) {   
                    $comment_mode = 0;
                } 
                elsif (!$comment_mode) {
                    push(@configfile, $_);
                }
            }
        }
    }
        
    if (($#ARGV + 1) < 1) {  #no command line args were passed  
        #if testcase filename is not passed on the command line, use files in config.xml  
        #parse test case file names from config.xml and build array
        foreach (@configfile) {
                
            if (/<testcasefile>/) {   
                $firstparse = $';  #print "$' \n\n";
                $firstparse =~ m~</testcasefile>~;
                $filename = $`;  #string between tags will be in $filename
                #print "\n$filename \n\n";
                push @casefilelist, $filename;  #add next filename we grab to end of array
            }
        }    
            
        unless ($casefilelist[0]) {
            if (-e "$dirname"."testcases.xml") {
                #not appending a $dirname here since we append one when we open the file
                push @casefilelist, "testcases.xml";  #if no files are specified in config.xml, default to testcases.xml
            }
            else {
                die "\nERROR: I can't find any test case files to run.\nYou must either use a config file or pass a filename " . 
                    "on the command line if you are not using the default testcase file (testcases.xml).";
            }
        }
    }
        
    elsif (($#ARGV + 1) == 1) {  #one command line arg was passed
        #use testcase filename passed on command line (config.xml is only used for other options)
        push @casefilelist, $ARGV[0];  #first commandline argument is the test case file, put this on the array for processing
    }
        
    elsif (($#ARGV + 1) == 2) {  #two command line args were passed
            
        undef $xnode; #reset xnode
        undef $xpath; #reset xpath
            
        $xpath = $ARGV[1];
            
        if ($xpath =~ /\/(.*)\[/) {  #if the argument contains a "/" and "[", it is really an XPath  
            $xpath =~ /(.*)\/(.*)\[(.*?)\]/;  #if it contains XPath info, just grab the file name
            $xnode = $3;  #grab the XPath Node value.. (from inside the "[]")
            #print "\nXPath Node is: $xnode \n";
        }
        else {
            print STDERR "\nSorry, $xpath is not in the XPath format I was expecting, I'm ignoring it...\n"; 
        }
            
        #use testcase filename passed on command line (config.xml is only used for other options)        
        push @casefilelist, $ARGV[0];  #first command line argument is the test case file, put this on the array for processing
    }
        
    elsif (($#ARGV + 1) > 2) {  #too many command line args were passed
        die "\nERROR: Too many arguments\n\n";
    }
        
    #print "\ntestcase file list: @casefilelist\n\n";
        
        
    #grab values for constants in config file:
    foreach (@configfile) {

        for my $config_const (qw/baseurl baseurl1 baseurl2 gnuplot proxy timeout
                globaltimeout globalhttplog standaloneplot/) {

            if (/<$config_const>/) {
                $_ =~ m~<$config_const>(.*)</$config_const>~;
                $config{$config_const} = $1;
                #print "\n$_ : $config{$_} \n\n";
            }
        }
            
        if (/<reporttype>/) {   
            $_ =~ m~<reporttype>(.*)</reporttype>~;
	    if ($1 ne "standard") {
               $reporttype = $1;
	       $nooutput = "set";
	    } 
            #print "\nreporttype : $reporttype \n\n";
        }    
            
        if (/<useragent>/) {   
            $_ =~ m~<useragent>(.*)</useragent>~;
            $setuseragent = $1;
            if ($setuseragent) { #http useragent that will show up in webserver logs
                $useragent->agent($setuseragent);
            }  
            #print "\nuseragent : $setuseragent \n\n";
        }
         
        if (/<httpauth>/) {
                #each time we see an <httpauth>, we set @authentry to be the
                #array of values, then we use [] to get a reference to that array
                #and push that reference onto @httpauth.             
	    my @authentry;
            $_ =~ m~<httpauth>(.*)</httpauth>~;
            @authentry = split(/:/, $1);
            if ($#authentry != 4) {
                print STDERR "\nError: httpauth should have 5 fields delimited by colons\n\n"; 
            }
            else {
		push(@httpauth, [@authentry]);
	    }
            #print "\nhttpauth : @httpauth \n\n";
        }
            
    }  
        
    close(CONFIG);
}
#------------------------------------------------------------------
sub convtestcases {  
    #here we do some pre-processing of the test case file and write it out to a temp file.
    #we convert certain chars so xml parser doesn't puke.
        
    my @xmltoconvert;        
        
    open(XMLTOCONVERT, "$dirname"."$currentcasefile") or die "\nError: Failed to open test case file\n\n";  #open file handle   
    @xmltoconvert = <XMLTOCONVERT>;  #read the file into an array
        
    $casecount = 0;
        
    foreach (@xmltoconvert){ 
            
        #convert escaped chars and certain reserved chars to temporary values that the parser can handle
        #these are converted back later in processing
        s/&/{AMPERSAND}/g;  
        s/\\</{LESSTHAN}/g;      
            
        #count cases while we are here    
        if ($_ =~ /<case/) {  #count test cases based on '<case' tag
            $casecount++; 
        }    
    }  
        
    close(XMLTOCONVERT);   
        
    open(XMLTOCONVERT, ">$dirname"."$currentcasefile".".$$".".tmp") or die "\nERROR: Failed to open temp file for writing\n\n";  #open file handle to temp file  
    print XMLTOCONVERT @xmltoconvert;  #overwrite file with converted array
    close(XMLTOCONVERT);
}
#------------------------------------------------------------------
sub fixsinglecase{ #xml parser creates a hash in a different format if there is only a single testcase.
                   #add a dummy testcase to fix this situation
        
    my @xmltoconvert;
        
    if ($casecount == 1) {
            
        open(XMLTOCONVERT, "$dirname"."$currentcasefile".".$$".".tmp") or die "\nError: Failed to open temp file\n\n";  #open file handle   
        @xmltoconvert = <XMLTOCONVERT>;  #read the file into an array
            
        for(@xmltoconvert) { 
            s/<\/testcases>/<case id="2" description1="dummy test case"\/><\/testcases>/g;  #add dummy test case to end of file   
        }       
        close(XMLTOCONVERT);
            
        open(XMLTOCONVERT, ">$dirname"."$currentcasefile".".$$".".tmp") or die "\nERROR: Failed to open temp file for writing\n\n";  #open file handle   
        print XMLTOCONVERT @xmltoconvert;  #overwrite file with converted array
        close(XMLTOCONVERT);
    }
}
#------------------------------------------------------------------
sub convertbackxml() {  #converts replaced xml with substitutions

    $_[0] =~ s~{AMPERSAND}~&~g;
    $_[0] =~ s~{LESSTHAN}~<~g;
    $_[0] =~ s~{TIMESTAMP}~$timestamp~g;
    $_[0] =~ s~{BASEURL}~$config{baseurl}~g;
    $_[0] =~ s~{BASEURL1}~$config{baseurl1}~g;
    $_[0] =~ s~{BASEURL2}~$config{baseurl2}~g;
    $_[0] =~ s~{PARSEDRESULT}~$parsedresult{parseresponse}~g; 
    $_[0] =~ s~{PARSEDRESULT1}~$parsedresult{parseresponse1}~g; 
    $_[0] =~ s~{PARSEDRESULT2}~$parsedresult{parseresponse2}~g; 
    $_[0] =~ s~{PARSEDRESULT3}~$parsedresult{parseresponse3}~g; 
    $_[0] =~ s~{PARSEDRESULT4}~$parsedresult{parseresponse4}~g; 
    $_[0] =~ s~{PARSEDRESULT5}~$parsedresult{parseresponse5}~g;
}
#------------------------------------------------------------------
sub url_escape {  #escapes difficult characters with %hexvalue
    #LWP handles url encoding already, but use this to escape valid chars that LWP won't convert (like +)
        
    my @a = @_;  #make a copy of the arguments
        
    map { s/[^-\w.,!~'()\/ ]/sprintf "%%%02x", ord $&/eg } @a;
    return wantarray ? @a : $a[0];
}
#------------------------------------------------------------------
sub httplog {  #write requests and responses to http.log file
        
    unless ($reporttype) {  #we suppress most logging when running in a plugin mode
        
        if ($case{logrequest} && ($case{logrequest} =~ /yes/i)) {  #http request - log setting per test case
            print HTTPLOGFILE $request->as_string, "\n\n";
        } 
            
        if ($case{logresponse} && ($case{logresponse} =~ /yes/i)) {  #http response - log setting per test case
            print HTTPLOGFILE $response->as_string, "\n\n";
        }
            
        if ($config{globalhttplog} && ($config{globalhttplog} =~ /yes/i)) {  #global http log setting
            print HTTPLOGFILE $request->as_string, "\n\n";
            print HTTPLOGFILE $response->as_string, "\n\n";
        }
            
        if (($config{globalhttplog} && ($config{globalhttplog} =~ /onfail/i)) && ($isfailure > 0)) { #global http log setting - onfail mode
            print HTTPLOGFILE $request->as_string, "\n\n";
            print HTTPLOGFILE $response->as_string, "\n\n";
        }
            
        if (($case{logrequest} && ($case{logrequest} =~ /yes/i)) or
            ($case{logresponse} && ($case{logresponse} =~ /yes/i)) or
            ($config{globalhttplog} && ($config{globalhttplog} =~ /yes/i)) or
            (($config{globalhttplog} && ($config{globalhttplog} =~ /onfail/i)) && ($isfailure > 0))
           ) {     
                print HTTPLOGFILE "\n************************* LOG SEPARATOR *************************\n\n\n";
        }
    }
}
#------------------------------------------------------------------
sub plotlog {  #write performance results to plot.log in the format gnuplot can use
        
    our (%months, $date, $time, $mon, $mday, $hours, $min, $sec, $year, $value);
        
    #do this unless: monitor is disabled in gui, or running standalone mode without config setting to turn on plotting     
    unless ((($gui == 1) and ($monitorenabledchkbx eq 'monitor_off')) or (($gui == 0) and ($config{standaloneplot} ne 'on'))) {  
            
        %months = ("Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4, "May" => 5, "Jun" => 6, 
                   "Jul" => 7, "Aug" => 8, "Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12);
            
        local ($value) = @_; 
        $date = scalar localtime; 
        ($mon, $mday, $hours, $min, $sec, $year) = $date =~ 
            /\w+ (\w+) +(\d+) (\d\d):(\d\d):(\d\d) (\d\d\d\d)/;
            
        $time = "$months{$mon} $mday $hours $min $sec $year";
            
        if ($plotclear eq 'yes') {  #used to clear the graph when requested
            open(PLOTLOG, ">$dirname"."plot.log") or die "ERROR: Failed to open file plot.log\n";  #open in clobber mode so log gets truncated
            $plotclear = 'no';  #reset the value 
        }
        else {
            open(PLOTLOG, ">>$dirname"."plot.log") or die "ERROR: Failed to open file plot.log\n";  #open in append mode
        }
          
        printf PLOTLOG "%s %2.4f\n", $time, $value;
        close(PLOTLOG);
    }    
}
#------------------------------------------------------------------
sub gnuplotcfg {  #create gnuplot config file
        
    #do this unless: monitor is disabled in gui, or running standalone mode without config setting to turn on plotting     
    unless ((($gui == 1) and ($monitorenabledchkbx eq 'monitor_off')) or (($gui == 0) and ($config{standaloneplot} ne 'on'))) {  
        
        open(GNUPLOTPLT, ">$dirname"."plot.plt") || die "Could not open file\n";
        print GNUPLOTPLT qq|
set term png 
set output \"plot.png\"
set size 1.1,0.5
set pointsize .5
set xdata time 
set ylabel \"Response Time (seconds)\"
set yrange [0:]
set bmargin 2
set tmargin 2
set timefmt \"%m %d %H %M %S %Y\"
plot \"plot.log\" using 1:7 title \"Response Times" w $graphtype
|;      
        close(GNUPLOTPLT);
        
    }
}
#------------------------------------------------------------------
sub finaltasks {  #do ending tasks
        
    if ($gui == 1){ gui_stop(); }
        
    unless ($reporttype) {  #we suppress most logging when running in a plugin mode
        writefinalhtml();  #write summary and closing tags for results file
    }
        
    unless ($xnode or $reporttype) { #skip regular STDOUT output if using an XPath or $reporttype is set ("standard" does not set this) 
        writefinalstdout();  #write summary and closing tags for STDOUT
    }
        
    unless ($reporttype) {  #we suppress most logging when running in a plugin mode
        writefinalxml();  #write summary and closing tags for XML results file
    }
    
    unless ($reporttype) {  #we suppress most logging when running in a plugin mode
        #these handles shouldn't be open    
        close(HTTPLOGFILE);
        close(RESULTS);
        close(RESULTSXML);
    }    
        
        
    #plugin modes
    if ($reporttype) {  #return value is set which corresponds to a monitoring program
            
        #Nagios plugin compatibility
        if ($reporttype eq 'nagios') { #report results in Nagios format 
            #predefined exit codes for Nagios
            %exit_codes  = ('UNKNOWN' ,-1,
                            'OK'      , 0,
                            'WARNING' , 1,
                            'CRITICAL', 2,);

	    my $end = defined $config{globaltimeout} ? "$config{globaltimeout};;0" : ";;0";

            if ($casefailedcount > 0) {
	        print "WebInject CRITICAL - $returnmessage |time=$totalruntime;$end\n";
                exit $exit_codes{'CRITICAL'};
            }
            elsif (($config{globaltimeout}) && ($totalruntime > $config{globaltimeout})) { 
                print "WebInject WARNING - All tests passed successfully but global timeout ($config{globaltimeout} seconds) has been reached |time=$totalruntime;$end\n";
                exit $exit_codes{'WARNING'};
            }
            else {
                print "WebInject OK - All tests passed successfully in $totalruntime seconds |time=$totalruntime;$end\n";
                exit $exit_codes{'OK'};
            }
        }
            
        #MRTG plugin compatibility
        elsif ($reporttype eq 'mrtg') { #report results in MRTG format 
            if ($casefailedcount > 0) {
                print "$totalruntime\n$totalruntime\n\nWebInject CRITICAL - $returnmessage \n";
                exit(0);
            }
            else { 
                print "$totalruntime\n$totalruntime\n\nWebInject OK - All tests passed successfully in $totalruntime seconds \n";
                exit(0);
            }
        }
        
        #External plugin. To use it, add something like that in the config file:
        # <reporttype>external:/home/webinject/Plugin.pm</reporttype>
        elsif ($reporttype =~ /^external:(.*)/) { 
            unless (my $return = do $1) {
                die "couldn't parse $1: $@\n" if $@;
                die "couldn't do $1: $!\n" unless defined $return;
                die "couldn't run $1\n" unless $return;
            }
        }

        else {
            print STDERR "\nError: only 'nagios', 'mrtg', 'external', or 'standard' are supported reporttype values\n\n";
        }
            
    }
	
}
#------------------------------------------------------------------
sub whackoldfiles {  #delete any files leftover from previous run if they exist
        
    if (-e "$dirname"."plot.log") { unlink "$dirname"."plot.log"; } 
    if (-e "$dirname"."plot.plt") { unlink "$dirname"."plot.plt"; } 
    if (-e "$dirname"."plot.png") { unlink "$dirname"."plot.png"; }
    if (glob("$dirname"."*.xml.tmp")) { unlink glob("$dirname"."*.xml.tmp"); }
        
    #verify files are deleted, if not give the filesystem time to delete them before continuing    
    while ((-e "plot.log") or (-e "plot.plt") or (-e "plot.png") or (glob('*.xml.tmp'))) {
        sleep .5; 
    }
}
#------------------------------------------------------------------
sub plotit {  #call the external plotter to create a graph (if we are in the appropriate mode)
        
    #do this unless: monitor is disabled in gui, or running standalone mode without config setting to turn on plotting     
    unless ((($gui == 1) and ($monitorenabledchkbx eq 'monitor_off')) or (($gui == 0) and ($config{standaloneplot} ne 'on'))) {
        unless ($graphtype eq 'nograph') {  #do this unless its being called from the gui with No Graph set
            if ($config{gnuplot}) {  #if gnuplot is specified in config.xml, use it
                system "$config{gnuplot}", "plot.plt";  #plot it with gnuplot
            }
            elsif (($^O eq 'MSWin32') and (-e './wgnupl32.exe')) {  #check for Win32 exe 
                system "wgnupl32.exe", "plot.plt";  #plot it with gnuplot using exe
            }
            elsif ($gui == 1) {
                gui_no_plotter_found();  #if gnuplot not specified, notify on gui
            }
        }
    }
}
#------------------------------------------------------------------
sub getdirname {  #get the directory webinject engine is running from
        
    $dirname = $0;    
    $dirname =~ s~(.*/).*~$1~;  #for nix systems
    $dirname =~ s~(.*\\).*~$1~; #for windoz systems   
    if ($dirname eq $0) { 
        $dirname = './'; 
    }
}    
#------------------------------------------------------------------
sub getoptions {  #command line options
        
    Getopt::Long::Configure('bundling');
    GetOptions(
        'v|V|version'   => \$opt_version,
        'c|config=s'    => \$opt_configfile,
        'o|output=s'    => \$opt_output,
        'n|no-output'   => \$nooutput,
        ) 
        or do {
            print_usage();
            exit();
        };
    if ($opt_version) {
	print "WebInject version $version\nFor more info: http://www.webinject.org\n";
  	exit();
    }
    sub print_usage {
        print <<EOB
    Usage:
      webinject.pl [-c|--config config_file] [-o|--output output_location] [-n|--no-output] [testcase_file [XPath]]
      webinject.pl --version|-v
EOB
    }
}
#------------------------------------------------------------------
