#!/usr/bin/perl

#    Copyright 2004 Corey Goldberg (corey@goldb.org)
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


use LWP;
use HTTP::Cookies;
use XML::Simple;
use Time::HiRes 'time','sleep';
use Crypt::SSLeay;
#use Data::Dumper;  #to dump hashes for debugging   


$| = 1; #don't buffer output to STDOUT


if (($0 eq 'webinject.pl') or ($0 eq 'webinject.exe')) {  #set flag so we know if it is running standalone or from webinjectgui
    $gui = 0; engine();
}
else {
    $gui = 1;
    
    whackoldfiles(); #delete files leftover from previous run (do this here so they are whacked on startup when running from gui)
}






#------------------------------------------------------------------
sub engine  #wrap the whole engine in a subroutine so it can be integrated with the gui 
{   
    if ($gui == 1) {gui_initial();}
        
    $startruntimer = time();  #timer for entire test run
    $currentdatetime = localtime time;  #get current date and time for results report
        
    open(HTTPLOGFILE, ">http.log") or die "\nERROR: Failed to open http.log file\n\n";   
    open(RESULTS, ">results.html") or die "\nERROR: Failed to open results.html file\n\n";    
    open(RESULTSXML, ">results.xml") or die "\nERROR: Failed to open results.xml file\n\n";
    
    #delete files leftover from previous run (do this here so they are whacked each run)
    whackoldfiles();
      
    #contsruct objects
    $useragent = LWP::UserAgent->new;
    $cookie_jar = HTTP::Cookies->new;
    $useragent->agent('WebInject');  #http useragent that will show up in webserver logs
    if ($proxy) {$useragent->proxy(['http', 'https'], $proxy)}; #add proxy support if it is set in config.xml
        
        
    processcasefile();
        
    print RESULTSXML qq|<results>\n\n|;  #write initial xml tag
        
    writeinitialhtml();  #write opening tags for results file
        
    unless ($xnode) { #if using XPath, skip regular STDOUT output 
        writeinitialstdout();  #write opening tags for STDOUT. 
    }
        
        
    if ($gui != 1){$graphtype = 'lines';} #default to line graph if not in GUI
        
    if ($gui == 1){$curgraphtype = $graphtype;}  #set the initial value so we know if the user changes the graph setting from the gui
        
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
        
        
    foreach (@casefilelist) { #process test case files named in config.xml
        
        $currentcasefile = $_;
        #print "\n$currentcasefile\n\n";
            
        $testnum = 1;
        $casefilecheck = ' ';
            
        if ($gui == 1){gui_processing_msg();}
            
        convtestcases();
            
        fixsinglecase();
            
        $xmltestcases = XMLin("./$currentcasefile"); #slurp test case file to parse
        #print Dumper($xmltestcases);  #for debug, dump hash of xml   
        #print keys %{$configfile};  #print keys from dereferenced hash
            
        cleancases();
            
        $repeat = $xmltestcases->{repeat};  #grab the number of times to iterate test case file
        unless ($repeat) { $repeat = 1; }  #set to 1 in case it is not defined in test case file               
            
            
        foreach (1 .. $repeat) {
                
            while ($testnum <= $casecount) {
                    
                if ($xnode) {  #if an XPath Node is defined, only process the single Node 
                    $testnum = $xnode; 
                }
                 
                $isfailure = 0;
                    
                    
                if ($gui == 1){
                    gui_statusbar();  #update the statusbar
                        
                    unless ($monitorenabledchkbx eq 'monitor_off') {  #don't do this if monitor is disabled in gui
                        if ("$curgraphtype" ne "$graphtype") {  #check to see if the user changed the graph setting
                            gnuplotcfg();  #create the gnuplot config file since graph setting changed
                            $curgraphtype = $graphtype;
                        }
                    }
                }
                    
                    
                $timestamp = time();  #used to replace parsed {timestamp} with real timestamp value
                if ($verifypositivenext) {$verifylater = $verifypositivenext;}  #grab $verifypositivenext string from previous test case (if it exists)
                if ($verifynegativenext) {$verifylaterneg = $verifynegativenext;}  #grab $verifynegativenext string from previous test case (if it exists)
                    
                #populate variables with values from testcase file, do substitutions, and revert {AMPERSAND} back to "&"
                $description1 = $xmltestcases->{case}->{$testnum}->{description1}; if ($description1) {$description1 =~ s/{AMPERSAND}/&/g; $description1 =~ s/{TIMESTAMP}/$timestamp/g; if ($gui == 1){gui_tc_descript();}}
                $description2 = $xmltestcases->{case}->{$testnum}->{description2}; if ($description2) {$description2 =~ s/{AMPERSAND}/&/g; $description2 =~ s/{TIMESTAMP}/$timestamp/g;}  
                $method = $xmltestcases->{case}->{$testnum}->{method}; if ($method) {$method =~ s/{AMPERSAND}/&/g; $method =~ s/{TIMESTAMP}/$timestamp/g;}  
                $url = $xmltestcases->{case}->{$testnum}->{url}; if ($url) {$url =~ s/{AMPERSAND}/&/g; $url =~ s/{TIMESTAMP}/$timestamp/g; $url =~ s/{BASEURL}/$baseurl/g; 
                    $url =~ s/{PARSEDRESULT}/$parsedresult/g; $url =~ s/{PARSEDRESULT1}/$parsedresult1/g; $url =~ s/{PARSEDRESULT2}/$parsedresult2/g; $url =~ s/{PARSEDRESULT3}/$parsedresult3/g; 
                    $url =~ s/{PARSEDRESULT4}/$parsedresult4/g; $url =~ s/{PARSEDRESULT5}/$parsedresult5/g;}  
                $postbody = $xmltestcases->{case}->{$testnum}->{postbody}; if ($postbody) {$postbody =~ s/{AMPERSAND}/&/g; $postbody =~ s/{TIMESTAMP}/$timestamp/g; 
                    $postbody =~ s/{PARSEDRESULT}/$parsedresult/g; $url =~ s/{PARSEDRESULT1}/$parsedresult1/g; $postbody =~ s/{PARSEDRESULT2}/$parsedresult2/g; 
                    $postbody =~ s/{PARSEDRESULT3}/$parsedresult3/g; $postbody =~ s/{PARSEDRESULT4}/$parsedresult4/g; $postbody =~ s/{PARSEDRESULT5}/$parsedresult5/g;}  
                $verifypositive = $xmltestcases->{case}->{$testnum}->{verifypositive}; if ($verifypositive) {$verifypositive =~ s/{AMPERSAND}/&/g; 
                    $verifypositive =~ s/{TIMESTAMP}/$timestamp/g;}  
                $verifynegative = $xmltestcases->{case}->{$testnum}->{verifynegative}; if ($verifynegative) {$verifynegative =~ s/{AMPERSAND}/&/g; 
                    $verifynegative =~ s/{TIMESTAMP}/$timestamp/g;}  
                $verifypositivenext = $xmltestcases->{case}->{$testnum}->{verifypositivenext}; if ($verifypositivenext) {$verifypositivenext =~ s/{AMPERSAND}/&/g; $verifypositivenext =~ s/{TIMESTAMP}/$timestamp/g;}  
                $verifynegativenext = $xmltestcases->{case}->{$testnum}->{verifynegativenext}; if ($verifynegativenext) {$verifynegativenext =~ s/{AMPERSAND}/&/g; $verifynegativenext =~ s/{TIMESTAMP}/$timestamp/g;}  
                $parseresponse = $xmltestcases->{case}->{$testnum}->{parseresponse}; if ($parseresponse) {$parseresponse =~ s/{AMPERSAND}/&/g; $parseresponse =~ s/{TIMESTAMP}/$timestamp/g;}  
                $parseresponse1 = $xmltestcases->{case}->{$testnum}->{parseresponse1}; if ($parseresponse1) {$parseresponse1 =~ s/{AMPERSAND}/&/g; $parseresponse1 =~ s/{TIMESTAMP}/$timestamp/g;}
                $parseresponse2 = $xmltestcases->{case}->{$testnum}->{parseresponse2}; if ($parseresponse2) {$parseresponse2 =~ s/{AMPERSAND}/&/g; $parseresponse2 =~ s/{TIMESTAMP}/$timestamp/g;} 
                $parseresponse3 = $xmltestcases->{case}->{$testnum}->{parseresponse3}; if ($parseresponse3) {$parseresponse3 =~ s/{AMPERSAND}/&/g; $parseresponse3 =~ s/{TIMESTAMP}/$timestamp/g;} 
                $parseresponse4 = $xmltestcases->{case}->{$testnum}->{parseresponse4}; if ($parseresponse4) {$parseresponse4 =~ s/{AMPERSAND}/&/g; $parseresponse4 =~ s/{TIMESTAMP}/$timestamp/g;} 
                $parseresponse5 = $xmltestcases->{case}->{$testnum}->{parseresponse5}; if ($parseresponse5) {$parseresponse5 =~ s/{AMPERSAND}/&/g; $parseresponse5 =~ s/{TIMESTAMP}/$timestamp/g;} 
                $logrequest = $xmltestcases->{case}->{$testnum}->{logrequest}; if ($logrequest) {$logrequest =~ s/{AMPERSAND}/&/g; $logrequest =~ s/{TIMESTAMP}/$timestamp/g;}  
                $logresponse = $xmltestcases->{case}->{$testnum}->{logresponse}; if ($logresponse) {$logresponse =~ s/{AMPERSAND}/&/g; $logresponse =~ s/{TIMESTAMP}/$timestamp/g;}  
                $sleep = $xmltestcases->{case}->{$testnum}->{sleep}; if ($logresponse) {$logresponse =~ s/{AMPERSAND}/&/g; $logresponse =~ s/{TIMESTAMP}/$timestamp/g;}
                    
                    
                print RESULTS qq|<b>Test:  $currentcasefile - $testnum </b><br>\n|;
                unless ($xnode) { #if using XPath, skip regular STDOUT output 
                    print STDOUT qq|Test:  $currentcasefile - $testnum \n|;
                }
                    
                unless ($casefilecheck eq $currentcasefile) {
                    unless ($currentcasefile eq $casefilelist[0]) {  #if this is the first test case file, skip printing the closing tag for the previous one
                        print RESULTSXML qq|    </testcases>\n\n|;
                    }
                    print RESULTSXML qq|    <testcases file="$currentcasefile">\n\n|;
                }
                    
                print RESULTSXML qq|        <testcase id="$testnum">\n|;
                    
                if ($description1) {
                    print RESULTS qq|$description1 <br>\n|; 
                    unless ($xnode) { #if using XPath, skip regular STDOUT output 
                        print STDOUT qq|$description1 \n|;
                    }
                    print RESULTSXML qq|            <description1>$description1</description1>\n|; 
                }
                    
                if ($description2) {
                    print RESULTS qq|$description2 <br>\n|;
                    unless ($xnode) { #if using XPath, skip regular STDOUT output 
                        print STDOUT qq|$description2 \n|;
                    }
                    print RESULTSXML qq|            <description2>$description2</description2>\n|; 
                }
                    
                print RESULTS qq|<br>\n|;
                    
                if ($verifypositive) {
                    print RESULTS qq|Verify: "$verifypositive" <br>\n|;
                    unless ($xnode) { #if using XPath, skip regular STDOUT output 
                        print STDOUT qq|Verify: "$verifypositive" \n|;
                    }
                    print RESULTSXML qq|            <verifypositive>$verifypositive</verifypositive>\n|; 
                }
                    
                if ($verifynegative) { 
                    print RESULTS qq|Verify Negative: "$verifynegative" <br>\n|;
                    unless ($xnode) { #if using XPath, skip regular STDOUT output 
                        print STDOUT qq|Verify Negative: "$verifynegative" \n|;
                    }
                    print RESULTSXML qq|            <verifynegative>$verifynegative</verifynegative>\n|; 
                }
                    
                if ($verifypositivenext) { 
                    print RESULTS qq|Verify On Next Case: "$verifypositivenext" <br>\n|;
                    unless ($xnode) { #if using XPath, skip regular STDOUT output 
                        print STDOUT qq|Verify On Next Case: "$verifypositivenext" \n|;
                    }
                    print RESULTSXML qq|            <verifypositivenext>$verifypositivenext</verifypositivenext>\n|; 
                }
                    
                if ($verifynegativenext) { 
                    print RESULTS qq|Verify Negative On Next Case: "$verifynegativenext" <br>\n|;
                    unless ($xnode) { #if using XPath, skip regaular STDOUT output 
                        print STDOUT qq|Verify Negative On Next Case: "$verifynegativenext" \n|;
                    }
                    print RESULTSXML qq|            <verifynegativenext>$verifynegativenext</verifynegativenext>\n|; 
                }
                    
                    
                if ($method) {
                    if ($method eq "get") {httpget();}
                    elsif ($method eq "post") {httppost();}
                    else {print STDERR qq|ERROR: bad HTTP Request Method Type, you must use "get" or "post"\n|;}
                }
                else {   
                    httpget();  #use "get" if no method is specified  
                }  
                    
                    
                verify();  #verify result from http response
                    
                httplog();  #write to http.log file
                    
                plotlog($latency);  #send perf data to log file for plotting
                    
                plotit();  #call the external plotter to create a graph
                 
                if ($gui == 1) {gui_updatemontab();}  #update monitor with the newly rendered plot graph 
                    
                    
                parseresponse();  #grab string from response to send later
                    
                    
                if ($isfailure > 0) {  #if any verification fails, testcase is considered a failure
                    print RESULTS qq|<b><font color=red>TEST CASE FAILED</font></b><br>\n|;
                    if ($xnode) { #only print this way if using XPath
                        print STDOUT qq|pass|;
                    }                
                    unless ($xnode) { #if using XPath, skip regular STDOUT output 
                        print STDOUT qq|TEST CASE FAILED \n|;
                    }
                    print RESULTSXML qq|            <success>false</success>\n|;
                    if ($gui == 1){gui_status_failed();}
                    $casefailedcount++;
                }
                else {
                    print RESULTS qq|<b><font color=green>TEST CASE PASSED</font></b><br>\n|;
                    if ($xnode) { #only print this way if using XPath
                        print STDOUT qq|fail|;
                    }  
                    unless ($xnode) { #if using XPath, skip regular STDOUT output 
                        print STDOUT qq|TEST CASE PASSED \n|;
                    }
                    print RESULTSXML qq|            <success>true</success>\n|;
                    if ($gui == 1){gui_status_passed();}
                    $casepassedcount++;
                }
                    
                    
                print RESULTS qq|Response Time = $latency sec <br>\n|;
                if ($gui == 1) {gui_timer_output();} 
                unless ($xnode) { #if using XPath, skip regular STDOUT output 
                    print STDOUT qq|Response Time = $latency sec \n|;
                }
                print RESULTSXML qq|            <responsetime>$latency</responsetime>\n|;
                    
                print RESULTSXML qq|        </testcase>\n\n|;
                    
                print RESULTS qq|<br>\n------------------------------------------------------- <br>\n\n|;
                unless ($xnode) { #if using XPath, skip regular STDOUT output 
                    print STDOUT qq|------------------------------------------------------- \n|;
                }
                    
                    
                    
                $casefilecheck = $currentcasefile;  #set this so <testcases> xml is only closed after each file is done processing
                    
                if ($xnode) {  #if an XPath Node is defined, only process the single Node 
                    $testnum = ($casecount + 1); 
                }
                    
                    
                $endruntimer = time();
                $totalruntime = (int(1000 * ($endruntimer - $startruntimer)) / 1000);  #elapsed time rounded to thousandths 
                    
                $testnum++;
                $totalruncount++;
                    
                if ($latency > $maxresponse) {$maxresponse = $latency;}  #set max response time
                if ($latency < $minresponse) {$minresponse = $latency;}  #set min response time
                $totalresponse = ($totalresponse + $latency);  #keep total of response times for calculating avg 
                $avgresponse = (int(1000 * ($totalresponse / $totalruncount)) / 1000);  #avg response rounded to thousandths
                    
                if ($gui == 1) {gui_updatemonstats();}  #update timers and counts in monitor tab   
                    
                #break from sub if user presses stop button in gui    
                if ($stop eq 'yes') {
                    finaltasks();
                    $stop = 'no';
                    return "";  #break from sub
                }
                    
                if ($sleep) {  #if a sleep parameter is set in the case, sleep that amount
                    sleep($sleep)
                }                    
                    
            }
                
            $testnum = 1;  #reset testcase counter so it will reprocess test case file if repeat is set
        }
    }
        
    finaltasks();  #do ending tasks
        
} #end engine subroutine



#------------------------------------------------------------------
#  SUBROUTINES
#------------------------------------------------------------------
sub writeinitialhtml {  #write opening tags for results file
        
    print RESULTS 
qq|    
<html>
<head>
    <title>WebInject Test Results</title>
    <style type="text/css">
        .title{FONT: 12px verdana, arial, helvetica, sans-serif; font-weight: bold}
        .text{FONT: 10px verdana, arial, helvetica, sans-serif}
        body {background-color: #F5F5F5;
              font-family: verdana, arial, helvetica, sans-serif;
              font-size: 10px;
              scrollbar-base-color: #999999;
              color: #000000;}
    </style>
</head>
<body>
<hr>
-------------------------------------------------------<br>
|; 
}
#------------------------------------------------------------------
sub writeinitialstdout {  #write opening tags for STDOUT

    print STDOUT 
qq|
Starting Webinject Engine... 
-------------------------------------------------------
|; 
}
#------------------------------------------------------------------
sub writefinalhtml {  #write summary and closing tags for results file
        
    print RESULTS
qq|    
<br><hr><br>
<b>
Start Time: $currentdatetime <br>
Total Run Time: $totalruntime  seconds <br>
<br>
Test Cases Run: $totalruncount <br>
Test Cases Passed: $casepassedcount <br>
Test Cases Failed: $casefailedcount <br>
Verifications Passed: $passedcount <br>
Verifications Failed: $failedcount <br>
<br>
Average Response Time: $avgresponse  seconds <br>
Max Response Time: $maxresponse  seconds <br>
Min Response Time: $minresponse  seconds <br>
</b>
<br>

</body>
</html>
|; 
}
#------------------------------------------------------------------
sub writefinalstdout {  #write summary and closing tags for STDOUT
        
    print STDOUT
qq|    
Start Time: $currentdatetime
Total Run Time: $totalruntime  seconds

Test Cases Run: $totalruncount
Test Cases Passed: $casepassedcount
Test Cases Failed: $casefailedcount 
Verifications Passed: $passedcount
Verifications Failed: $failedcount
|; 
}
#------------------------------------------------------------------
sub httpget {  #send http request and read response
        
    $request = new HTTP::Request('GET',"$url");
        
    $cookie_jar->add_cookie_header($request);
    #print $request->as_string; print "\n\n";
        
    $starttimer = time();
    $response = $useragent->simple_request($request);
    $endtimer = time();
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  #elapsed time rounded to thousandths 
    #print $response->as_string; print "\n\n";
        
    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n";
}
#------------------------------------------------------------------
sub httppost {  #send http request and read response
        
    $request = new HTTP::Request('POST',"$url");
    $request->content_type('application/x-www-form-urlencoded');
    $request->content($postbody);
    $cookie_jar->add_cookie_header($request);
    #print $request->as_string; print "\n\n";
        
    $starttimer = time();
    $response = $useragent->simple_request($request);
    $endtimer = time();
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  #elapsed time rounded to thousandths 
    #print $response->as_string; print "\n\n";
        
    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n";
}
#------------------------------------------------------------------
sub verify {  #do verification of http response and print status to HTML/XML and UI
        
    if ($verifypositive) {
        if ($response->as_string() =~ /$verifypositive/i) {  #verify existence of string in response
            print RESULTS "<font color=green>Passed Positive Verification</font><br>\n";
            unless ($xnode) { #if using XPath, skip regular STDOUT output 
                print STDOUT "Passed Positive Verification \n";
            }
            $passedcount++;
        }
        else {
            print RESULTS "<font color=red>Failed Positive Verification</font><br>\n";
            unless ($xnode) { #if using XPath, skip regular STDOUT output 
                print STDOUT "Failed Positive Verification \n";         
            }
            $failedcount++;
            $isfailure++;
        }
    }
        
        
        
    if ($verifynegative)
    {
        if ($response->as_string() =~ /$verifynegative/i) {  #verify existence of string in response
            print RESULTS "<font color=red>Failed Negative Verification</font><br>\n";
            unless ($xnode) { #if using XPath, skip regular STDOUT output 
                print STDOUT "Failed Negative Verification \n";            
            }
            $failedcount++;
            $isfailure++;
        }
        else {
            print RESULTS "<font color=green>Passed Negative Verification</font><br>\n";
            unless ($xnode) { #if using XPath, skip regular STDOUT output 
                print STDOUT "Passed Negative Verification \n";
            }
            $passedcount++;                
        }
    }
        
        
        
    if ($verifylater) {
        if ($response->as_string() =~ /$verifylater/i) {  #verify existence of string in response
            print RESULTS "<font color=green>Passed Positive Verification (verification set in previous test case)</font><br>\n";
            unless ($xnode) { #if using XPath, skip regular STDOUT output 
                print STDOUT "Passed Positive Verification (verification set in previous test case) \n";
            }
            $passedcount++;
        }
        else {
            print RESULTS "<font color=red>Failed Positive Verification (verification set in previous test case)</font><br>\n";
            unless ($xnode) { #if using XPath, skip regular STDOUT output 
                print STDOUT "Failed Positive Verification (verification set in previous test case) \n";            
            }
            $failedcount++;
            $isfailure++;            
        }
        
        $verifylater = '';  #set to null after verification
    }
        
        
        
    if ($verifylaterneg) {
        if ($response->as_string() =~ /$verifylaterneg/i) {  #verify existence of string in response
            print RESULTS "<font color=red>Failed Negative Verification (negative verification set in previous test case)</font><br>\n";
            unless ($xnode) { #if using XPath, skip regular STDOUT output 
                print STDOUT "Failed Negative Verification (negative verification set in previous test case) \n";     
            }
            $failedcount++;
            $isfailure++;
        }
        else {
            print RESULTS "<font color=green>Passed Negative Verification (negative verification set in previous test case)</font><br>\n";
            unless ($xnode) { #if using XPath, skip regular STDOUT output 
                print STDOUT "Passed Negative Verification (negative verification set in previous test case) \n";
            }
            $passedcount++;                   
        }
        
        $verifylaterneg = '';  #set to null after verification
    }
        
        
        
    #verify http response code is in the 100-399 range    
    if ($response->as_string() =~ /HTTP\/1.(0|1) (1|2|3)/i) {  #verify existance of string in response
        print RESULTS "<font color=green>Passed HTTP Response Code Verification (not in error range)</font><br>\n"; 
        unless ($xnode) { #if using XPath, skip regular STDOUT output 
            print STDOUT "Passed HTTP Response Code Verification (not in error range) \n"; 
        }
        #succesful response codes (100-399)
        $passedcount++;         
    }
    else {
        $response->as_string() =~ /(HTTP\/1.)(.*)/i;
        if ($1) {  #this is true if an HTTP response returned 
            print RESULTS "<font color=red>Failed HTTP Response Code Verification ($1$2)</font><br>\n"; #($1$2) is http response code
            unless ($xnode) { #if using XPath, skip regular STDOUT output 
                print STDOUT "Failed HTTP Response Code Verification ($1$2) \n"; #($1$2) is http response code   
            }
        }
        else {  #no HTTP response returned.. could be error in connection, bad hostname/address, or can not connect to web server
        print RESULTS "<font color=red>Failed - No Response</font><br>\n"; #($1$2) is http response code
            unless ($xnode) { #if using XPath, skip regular STDOUT output 
                print STDOUT "Failed - No Response \n"; #($1$2) is http response code   
            }
        }
        $failedcount++;
        $isfailure++;
    }
        
}
#------------------------------------------------------------------
sub parseresponse {  #parse values from responses for use in future request (for session id's, dynamic URL rewriting, etc)
        
    if ($parseresponse) {
           
        @parseargs = split (/\|/, $parseresponse);
            
        $leftboundary = $parseargs[0]; $rightboundary = $parseargs[1]; $escape = $parseargs[2];
            
        $resptoparse = $response->as_string;
        if ($resptoparse =~ /$leftboundary(.*?)$rightboundary/) {
            $parsedresult = $1; 
        }
            
        if ($escape) {
            if ($escape eq 'escape') {
                $parsedresult = url_escape($parsedresult);
            }
        }
        #print "\n\nParsed String: $parsedresult\n\n";
    }
        
        
    if ($parseresponse1) {
            
        @parseargs = split (/\|/, $parseresponse1);
            
        $leftboundary = $parseargs[0]; $rightboundary = $parseargs[1]; $escape = $parseargs[2];
            
        $resptoparse = $response->as_string;
        if ($resptoparse =~ /$leftboundary(.*?)$rightboundary/) {
            $parsedresult1 = $1; 
        }
            
        if ($escape) {
            if ($escape eq 'escape') {
                $parsedresult1 = url_escape($parsedresult1);
            }
        }
        #print "\n\nParsed String: $parsedresult1\n\n";
    }
        
        
    if ($parseresponse2) {
            
        @parseargs = split (/\|/, $parseresponse2);
            
        $leftboundary = $parseargs[0]; $rightboundary = $parseargs[1]; $escape = $parseargs[2];
            
        $resptoparse = $response->as_string;
        if ($resptoparse =~ /$leftboundary(.*?)$rightboundary/) {
            $parsedresult2 = $1; 
        }
            
        if ($escape) {
            if ($escape eq 'escape') {
                $parsedresult2 = url_escape($parsedresult2);
            }
        }
        #print "\n\nParsed String: $parsedresult2\n\n";
    }
        
        
    if ($parseresponse3) {
            
        @parseargs = split (/\|/, $parseresponse3);
            
        $leftboundary = $parseargs[0]; $rightboundary = $parseargs[1]; $escape = $parseargs[2];
            
        $resptoparse = $response->as_string;
        if ($resptoparse =~ /$leftboundary(.*?)$rightboundary/) {
            $parsedresult3 = $1; 
        }
            
        if ($escape) {
            if ($escape eq 'escape') {
                $parsedresult3 = url_escape($parsedresult3);
            }
        }
        #print "\n\nParsed String: $parsedresult3\n\n";
    }
    
    
    if ($parseresponse4) {
            
        @parseargs = split (/\|/, $parseresponse4);
            
        $leftboundary = $parseargs[0]; $rightboundary = $parseargs[1]; $escape = $parseargs[2];
            
        $resptoparse = $response->as_string;
        if ($resptoparse =~ /$leftboundary(.*?)$rightboundary/) {
            $parsedresult4 = $1; 
        }
        
        if ($escape) {
            if ($escape eq 'escape') {
                $parsedresult4 = url_escape($parsedresult4);
            }
        }           
        #print "\n\nParsed String: $parsedresult4\n\n";
    }
        
        
    if ($parseresponse5) {
            
        @parseargs = split (/\|/, $parseresponse5);
            
        $leftboundary = $parseargs[0]; $rightboundary = $parseargs[1]; $escape = $parseargs[2];
            
        $resptoparse = $response->as_string;
        if ($resptoparse =~ /$leftboundary(.*?)$rightboundary/) {
            $parsedresult5 = $1; 
        }
            
        if ($escape) {
            if ($escape eq 'escape') {
                $parsedresult5 = url_escape($parsedresult5);
            }
        }
        #print "\n\nParsed String: $parsedresult5\n\n";
    }
        
}
#------------------------------------------------------------------
sub processcasefile {  #get test case files to run (from command line or config file) and evaluate constants
        
    undef @casefilelist; #empty the array
        
    if ($#ARGV < 0) {  #if testcase filename is not passed on the command line, use config.xml
            
        open(CONFIG, "config.xml") or die "\nERROR: Failed to open config.xml file\n\n";  #open file handle   
        @configfile = <CONFIG>;  #read the file into an array
            
        #parse test case file names from config.xml and build array
        foreach (@configfile) {
            
            if (/<testcasefile>/) {   
                $firstparse = $';  #print "$' \n\n";
                $firstparse =~ /<\/testcasefile>/;
                $filename = $`;  #string between tags will be in $filename
                #print "\n$filename \n\n";
                push @casefilelist, $filename;  #add next filename we grab to end of array
            }
        }    
            
        if ($casefilelist[0]) {}
        else {
            push @casefilelist, "testcases.xml";  #if no file specified in config.xml, default to testcases.xml
        }
    }
    else {  # use testcase filename passed on command line (config.xml is not used at all, even for other things)
            
        undef $xnode; #reset xnode
        undef $xpath; #reset xpath
            
        $xpath = $ARGV[1];
            
        if ($xpath =~ /\/(.*)\[/) {    #if the parameter contains a "/" and "[", it is really an XPath  
            $xpath =~ /(.*)\/(.*)\[(.*?)\]/;  #if it contains XPath info, just grab the file name
            $xnode = $3;  #grab the XPath Node value.. (from inside the "[]")
            #print "\nxpath node is: $xnode \n";
        }
        else {
            print STDERR "\nSorry, $xpath is not in the XPath format I was excpecting, I'm ingoring it...\n"; 
        }
            
            
        push @casefilelist, $ARGV[0];  #first commandline parameter is the test case file, put this on the array for processing
    }
        
    #print "\ntestcase file list: @casefilelist\n\n";
        
        
    #grab values for constants in config file:
    foreach (@configfile) {
            
        if (/<baseurl>/) {   
            $_ =~ /<baseurl>(.*)<\/baseurl>/;
            $baseurl = $1;
            #print "\n$baseurl \n\n";
        }
            
        if (/<proxy>/) {   
            $_ =~ /<proxy>(.*)<\/proxy>/;
            $proxy = $1;
            #print "\n$proxy \n\n";
        }
            
        if (/<useragent>/) {   
            $_ =~ /<useragent>(.*)<\/useragent>/;
            $setuseragent = $1;
            if ($setuseragent) { $useragent->agent($setuseragent); }  #http useragent that will show up in webserver logs
            #print "\n$setuseragent \n\n";
        }
         
        if (/<globalhttplog>/) {   
            $_ =~ /<globalhttplog>(.*)<\/globalhttplog>/;
            $globalhttplog = $1;
            #print "\n$globalhttplog \n\n";
        }
        
        if (/<gnuplot>/) {        
            $_ =~ /<gnuplot>(.*)<\/gnuplot>/;
            $gnuplot = $1;
            #print "\n$gnuplot \n\n";
        }
        
        if (/<standaloneplot>/) {        
            $_ =~ /<standaloneplot>(.*)<\/standaloneplot>/;
            $standaloneplot = $1;
            #print "\nstandaloneplot \n\n";
        }
            
    }  
        
    close(CONFIG);
}
#------------------------------------------------------------------
sub convtestcases {  #convert ampersands in test cases to {AMPERSAND} so xml parser doesn't puke
        
    open(XMLTOCONVERT, "$currentcasefile") or die "\nError: Failed to open test case file\n\n";  #open file handle   
    @xmltoconvert = <XMLTOCONVERT>;  #Read the file into an array
        
    $casecount = 0;
        
    foreach (@xmltoconvert){ 
        
        s/&/{AMPERSAND}/g;  #convert ampersands (&) &'s are malformed XML
        
        if ($_ =~ /<case/) #count test cases based on '<case' tag
        {
            $casecount++; 
        }    
    }  
        
    close(XMLTOCONVERT);   
        
    open(XMLTOCONVERT, ">$currentcasefile") or die "\nERROR: Failed to open test case file\n\n";  #open file handle   
    print XMLTOCONVERT @xmltoconvert; #overwrite file with converted array
    close(XMLTOCONVERT);
}
#------------------------------------------------------------------
sub fixsinglecase{ #xml parser creates a hash in a different format if there is only a single testcase.
                   #add a dummy testcase to fix this situation
        
    if ($casecount == 1) {
        
        open(XMLTOCONVERT, "$currentcasefile") or die "\nError: Failed to open test case file\n\n";  #open file handle   
        @xmltoconvert = <XMLTOCONVERT>;  #Read the file into an array
        
        for(@xmltoconvert) { 
            s/<\/testcases>/<case id="2" description1="dummy test case"\/><\/testcases>/g;  #add dummy test case to end of file   
        }       
        close(XMLTOCONVERT);
        
        open(XMLTOCONVERT, ">$currentcasefile") or die "\nERROR: Failed to open test case file\n\n";  #open file handle   
        print XMLTOCONVERT @xmltoconvert; #overwrite file with converted array
        close(XMLTOCONVERT);
    }
}
#------------------------------------------------------------------
sub cleancases {  #cleanup conversions made to file for ampersands and single testcase instance
        
    open(XMLTOCONVERT, "$currentcasefile") or die "\nError: Failed to open test case file\n\n";  #open file handle   
    @xmltoconvert = <XMLTOCONVERT>;  #Read the file into an array
        
    foreach (@xmltoconvert) { 
        
        s/{AMPERSAND}/&/g;  #convert ampersands (&) &'s are malformed XML
        
        s/<case id="2" description1="dummy test case"\/><\/testcases>/<\/testcases>/g;  #add dummy test case to end of file
    }  
        
    close(XMLTOCONVERT);   
        
    open(XMLTOCONVERT, ">$currentcasefile") or die "\nERROR: Failed to open test case file\n\n";  #open file handle   
    print XMLTOCONVERT @xmltoconvert; #overwrite file with converted array
    close(XMLTOCONVERT);
}
#------------------------------------------------------------------
sub url_escape {  #escapes difficult characters with %hexvalue
    #LWP handles url encoding already, but use this to escape valid chars that LWP won't convert (like +)
        
    my @a = @_;  # make a copy of the arguments
    map { s/[^-\w.,!~'()\/ ]/sprintf "%%%02x", ord $&/eg } @a;
    return wantarray ? @a : $a[0];
}
#------------------------------------------------------------------
sub httplog {  #write requests and responses to http.log file
        
    if ($logrequest && ($logrequest =~ /yes/i)) {  #http request - log setting per test case
        print HTTPLOGFILE $request->as_string, "\n\n";
    } 
        
    if ($logresponse && ($logresponse =~ /yes/i)) {  #http response - log setting per test case
        print HTTPLOGFILE $response->as_string, "\n\n";
    }
        
    if ($globalhttplog && ($globalhttplog =~ /yes/i)) {  #global http log setting
        print HTTPLOGFILE $request->as_string, "\n\n";
        print HTTPLOGFILE $response->as_string, "\n\n";
    }
        
    if (($globalhttplog && ($globalhttplog =~ /onfail/i)) && ($isfailure > 0)) { #global http log setting - onfail mode
        print HTTPLOGFILE $request->as_string, "\n\n";
        print HTTPLOGFILE $response->as_string, "\n\n";
    }
}
#------------------------------------------------------------------
sub plotlog {  #write performance results to plot.log in the format gnuplot can use
        
    #do this unless: monitor is disabled in gui, or running standalone mode without config setting to turn on plotting     
    unless ((($gui == 1) and ($monitorenabledchkbx eq 'monitor_off')) or (($gui == 0) and ($standaloneplot ne 'on'))) {  
        
        %months = ("Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4, "May" => 5, "Jun" => 6, 
                   "Jul" => 7, "Aug" => 8, "Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12);
            
        local ($value) = @_; 
        $date = scalar localtime; 
        ($mon, $mday, $hours, $min, $sec, $year) = $date =~ 
            /\w+ (\w+) +(\d+) (\d\d):(\d\d):(\d\d) (\d\d\d\d)/;
            
        $time = "$months{$mon} $mday $hours $min $sec $year";
            
        if ($plotclear eq 'yes') {  #used to clear the graph when requested
            open(PLOTLOG, ">plot.log") or die "ERROR: Failed to open file plot.log\n";  #open in clobber mode so log gets truncated
            $plotclear = 'no';  #reset the value 
        }
        else {
            open(PLOTLOG, ">>plot.log") or die "ERROR: Failed to open file plot.log\n";  #open in append mode
        }
          
        printf PLOTLOG "%s %2.4f\n", $time, $value;
        close(PLOTLOG);
    }    
}
#------------------------------------------------------------------
sub gnuplotcfg {  #create gnuplot config file
    
    #do this unless: monitor is disabled in gui, or running standalone mode without config setting to turn on plotting     
    unless ((($gui == 1) and ($monitorenabledchkbx eq 'monitor_off')) or (($gui == 0) and ($standaloneplot ne 'on'))) {  
    
        open(GNUPLOTPLT, ">plot.plt") || die "Could not open file\n";
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
        
    if ($gui == 1){gui_stop();}
        
    writefinalhtml();  #write summary and closing tags for results file
        
    unless ($xnode) { #if using XPath, skip regular STDOUT output 
        writefinalstdout();  #write summary and closing tags for STDOUT
    }
        
    print RESULTSXML qq|    </testcases>\n\n</results>\n|;  #write final xml tag
        
    close(HTTPLOGFILE);
    close(RESULTS);
    close(RESULTSXML);
}
#------------------------------------------------------------------
sub whackoldfiles {  #delete any files leftover from previous run if they exist
        
    if (-e "plot.log") { unlink "plot.log"; } 
    if (-e "plot.plt") { unlink "plot.plt"; } 
    if (-e "plot.png") { unlink "plot.png"; }
        
    #verify files are deleted, if not give the filesystem time to delete them before continuing    
    while ((-e "plot.log") or (-e "plot.plt") or (-e "plot.png")) {
        sleep .5; 
    }
}
#------------------------------------------------------------------
sub plotit {  #call the external plotter to create a graph (if we are in the appropriate mode)
        
    #do this unless: monitor is disabled in gui, or running standalone mode without config setting to turn on plotting     
    unless ((($gui == 1) and ($monitorenabledchkbx eq 'monitor_off')) or (($gui == 0) and ($standaloneplot ne 'on'))) { 
        unless ($graphtype eq 'nograph') {  #do this unless its being called from the gui with No Graph set
            if ($gnuplot) {  #if gnuplot is specified in config.xml, use it
                system "$gnuplot", "plot.plt";  #plot it with gnuplot
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