#!/usr/bin/perl

#    Copyright 2004 Corey Goldberg (corey@test-tools.net)
#
#    This file is part of WebInject.
#
#    WebInject is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    WebInject is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with WebInject; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA



use LWP;
use HTTP::Cookies;
use Crypt::SSLeay;
use XML::Simple;
use Time::HiRes 'time','sleep';
use Tk;
use Tk::Stderr;
use Tk::ROText;
use Tk::Compound;
use Tk::ProgressBar::Mac;
#use Data::Dumper;  #to dump hashes for debugging   


$| = 1; #don't buffer output to STDOUT


 
$mw = MainWindow->new(-title  => 'WebInject - HTTP Test Tool',
                      -width  => '650', 
                      -height => '650', 
                      -bg     => '#666699',
                      );
$mw->InitStderr; #redirect all STDERR to a window
 
 
$mw->update();
$icon = $mw->Photo(-file => 'icon.gif');
$mw->iconimage($icon);


$mw ->Photo('logogif', -file => "logo.gif");    
$mw ->Label(-image => 'logogif', 
            -bg    => '#666699'
            )->place(qw/-x 235 -y 12/); $mw->update();


$mw ->Label(-text  => 'Engine Status:',
            -bg    => '#666699'
            )->place(qw/-x 25 -y 110/); $mw->update();


$out_window = $mw->Scrolled(ROText,  #engine status window 
                   -scrollbars  => 'e',
                   -background  => '#EFEFEF',
                   -width       => '85',
                   -height      => '7',
                  )->place(qw/-x 25 -y 128/); $mw->update(); 


$mw ->Label(-text  => 'Test Case Status:',
            -bg    => '#666699'
            )->place(qw/-x 25 -y 238/); $mw->update(); 


$status_window = $mw->Scrolled(ROText,  #test case status window 
                   -scrollbars  => 'e',
                   -background  => '#EFEFEF',
                   -width       => '85',
                   -height      => '26',
                  )->place(qw/-x 25 -y 256/); $mw->update();


$rtc_button = $mw->Button->Compound;
$rtc_button->Text(-text => "Run Test Cases");
$rtc_button = $mw->Button(-width              => '85',
                          -height             => '13',
                          -background         => '#EFEFEF',
                          -activebackground   => '#666699',
                          -foreground         => '#000000',
                          -activeforeground   => '#FFFFFF',
                          -borderwidth        => '3',
                          -image              => $rtc_button,
                          -command            => sub{engine();}
                          )->place(qw/-x 25 -y 75/); $mw->update();


$exit_button = $mw->Button->Compound;
$exit_button->Text(-text => "Exit");
$exit_button = $mw->Button(-width              => '40',
                           -height             => '13',
                           -background         => '#EFEFEF',
                           -activebackground   => '#666699',
                           -foreground         => '#000000',
                           -activeforeground   => '#FFFFFF',
                           -borderwidth        => '3',
                           -image              => $exit_button,
                           -command            => sub{exit;}
                           )->place(qw/-x 596 -y 5/); $mw->update();


$progressbar = $mw->ProgressBar(-width  => '420', 
                                -bg     => '#666699'
                                )->place(qw/-x 150 -y 75/); $mw->update();



MainLoop;





#------------------------------------------------------------------
sub engine 
{   
    $out_window->delete('0.0','end');    #clear window before starting
    $status_window->delete('0.0','end'); #clear window before starting
    
    $rtc_button->configure(-state       => 'disabled',  #disable button while running
                           -background  => '#666699',
                           );
    

    $startruntimer = time();  #timer for entire test run
    
    $currentdatetime = localtime time;  #get current date and time for results report

    $out_window->insert("end", "Starting Webinject Engine... \n\n"); $out_window->see("end");
    
    open(HTTPLOGFILE, ">http.log") || die "\nERROR: Failed to open http.log file\n\n";   

    open(RESULTS, ">results.html") || die "\nERROR: Failed to open results.html file\n\n";    
      
    writeinitialhtml();
       
    processconfigfile();
    
    #contsruct objects
    $useragent = LWP::UserAgent->new;
    $cookie_jar = HTTP::Cookies->new;

    $totalruncount = 0;
    $passedcount = 0;
    $failedcount = 0;
    
    
    foreach (@casefilelist) #process test case files named in config.xml
    {
        $currentcasefile = $_;
        #print "\n$currentcasefile\n\n";
        
        $testnum = 1;
        
        $out_window->insert("end", "processing test case file:\n$currentcasefile\n\n"); $out_window->see("end");
     
        convtestcases();
        
        $xmltestcases = XMLin("./$currentcasefile"); #slurp test case file to parse
        #print Dumper($xmltestcases);  #for debug, dump hash of xml   
        #print keys %{$configfile};  #print keys from dereferenced hash
        
        
     
        #special handling for when only one test case exists (hash is referenced different than with multiples due to how the parser formats the hash)
        if ($casecount == 1)
        {  
            $percentcomplete = ($testnum/$casecount)*100;  
            $progressbar->set($percentcomplete);  #update progressbar with current status
            
            $timestamp = time();  #used to replace parsed {timestamp} with real timestamp value
            
            #populate variables with values from testcase file, do substitutions, and revert {AMPERSAND} back to "&"
            $description1 = $xmltestcases->{case}->{description1}; if ($description1) {$description1 =~ s/{AMPERSAND}/&/g; $description1 =~ s/{TIMESTAMP}/$timestamp/g;
                $status_window->insert("end", "- $description1\n"); $status_window->see("end");}  
            $description2 = $xmltestcases->{case}->{description2}; if ($description2) {$description2 =~ s/{AMPERSAND}/&/g; $description2 =~ s/{TIMESTAMP}/$timestamp/g;}  
            $method = $xmltestcases->{case}->{method}; if ($method) {$method =~ s/{AMPERSAND}/&/g; $method =~ s/{TIMESTAMP}/$timestamp/g;}  
            $url = $xmltestcases->{case}->{url}; if ($url) {$url =~ s/{AMPERSAND}/&/g; $url =~ s/{TIMESTAMP}/$timestamp/g; $url =~ s/{BASEURL}/$baseurl/g;}  
            $postbody = $xmltestcases->{case}->{postbody}; if ($postbody) {$postbody =~ s/{AMPERSAND}/&/g; $postbody =~ s/{TIMESTAMP}/$timestamp/g;}  
            $verifypositive = $xmltestcases->{case}->{verifypositive}; if ($verifypositive) {$verifypositive =~ s/{AMPERSAND}/&/g; $verifypositive =~ s/{TIMESTAMP}/$timestamp/g;}  
            $verifynegative = $xmltestcases->{case}->{verifynegative}; if ($verifynegative) {$verifynegative =~ s/{AMPERSAND}/&/g; $verifynegative =~ s/{TIMESTAMP}/$timestamp/g;}  
            $logrequest = $xmltestcases->{case}->{logrequest}; if ($logrequest) {$logrequest =~ s/{AMPERSAND}/&/g; $logrequest =~ s/{TIMESTAMP}/$timestamp/g;}  
            $logresponse = $xmltestcases->{case}->{logresponse}; if ($logresponse) {$logresponse =~ s/{AMPERSAND}/&/g; $logresponse =~ s/{TIMESTAMP}/$timestamp/g;}  
                       
            print RESULTS "<b>Test:  $currentcasefile - $testnum </b><br>\n";
            if ($description1) {print RESULTS "$description1 <br>\n";}
            if ($description2) {print RESULTS "$description2 <br>\n";}
            print RESULTS "<br>\n";
            if ($verifypositive) {print RESULTS "Verify: \"$verifypositive\" <br> \n";}
            if ($verifynegative) {print RESULTS "Verify Negative: \"$verifynegative\" <br> \n";}
            
            if($method)
            {
                if ($method eq "get")
                {   httpget();  }
                elsif ($method eq "post")
                {   httppost(); }
                else {print STDERR qq|ERROR: bad HTTP Request Method Type, you must use "get" or "post"\n|;}
                }
            else
            {   
                httpget(); #use "get" if no method is specified  
            }  
                
            verify();  #verify result from http response
            
            print RESULTS "Response Time = $latency s<br>\n";
            print RESULTS "<br>\n-------------------------------------------------------<br>\n\n";
            
            $testnum++;
            $totalruncount++;
        }
        
        
        while ($testnum <= $casecount) #make any changes here to special case above
        {             
            $percentcomplete = ($testnum/$casecount)*100;  
            $progressbar->set($percentcomplete);  #update progressbar with current status
            
            $timestamp = time();  #used to replace parsed {timestamp} with real timestamp value
            if ($verifypositivenext) {$verifylater = $verifypositivenext;}  #grab $verifypositivenext string from previous test case (if it exists)
            if ($verifynegativenext) {$verifylaterneg = $verifynegativenext;}  #grab $verifynegativenext string from previous test case (if it exists)
            
            #populate variables with values from testcase file, do substitutions, and revert {AMPERSAND} back to "&"
            $description1 = $xmltestcases->{case}->{$testnum}->{description1}; if ($description1) {$description1 =~ s/{AMPERSAND}/&/g; $description1 =~ s/{TIMESTAMP}/$timestamp/g;
                $status_window->insert("end", "- $description1\n"); $status_window->see("end");}  
            $description2 = $xmltestcases->{case}->{$testnum}->{description2}; if ($description2) {$description2 =~ s/{AMPERSAND}/&/g; $description2 =~ s/{TIMESTAMP}/$timestamp/g;}  
            $method = $xmltestcases->{case}->{$testnum}->{method}; if ($method) {$method =~ s/{AMPERSAND}/&/g; $method =~ s/{TIMESTAMP}/$timestamp/g;}  
            $url = $xmltestcases->{case}->{$testnum}->{url}; if ($url) {$url =~ s/{AMPERSAND}/&/g; $url =~ s/{TIMESTAMP}/$timestamp/g; $url =~ s/{BASEURL}/$baseurl/g;}  
            $postbody = $xmltestcases->{case}->{$testnum}->{postbody}; if ($postbody) {$postbody =~ s/{AMPERSAND}/&/g; $postbody =~ s/{TIMESTAMP}/$timestamp/g;}  
            $verifypositive = $xmltestcases->{case}->{$testnum}->{verifypositive}; if ($verifypositive) {$verifypositive =~ s/{AMPERSAND}/&/g; $verifypositive =~ s/{TIMESTAMP}/$timestamp/g;}  
            $verifynegative = $xmltestcases->{case}->{$testnum}->{verifynegative}; if ($verifynegative) {$verifynegative =~ s/{AMPERSAND}/&/g; $verifynegative =~ s/{TIMESTAMP}/$timestamp/g;}  
            $verifypositivenext = $xmltestcases->{case}->{$testnum}->{verifypositivenext}; if ($verifypositivenext) {$verifypositivenext =~ s/{AMPERSAND}/&/g; $verifypositivenext =~ s/{TIMESTAMP}/$timestamp/g;}  
            $verifynegativenext = $xmltestcases->{case}->{$testnum}->{verifynegativenext}; if ($verifynegativenext) {$verifynegativenext =~ s/{AMPERSAND}/&/g; $verifynegativenext =~ s/{TIMESTAMP}/$timestamp/g;}  
            $logrequest = $xmltestcases->{case}->{$testnum}->{logrequest}; if ($logrequest) {$logrequest =~ s/{AMPERSAND}/&/g; $logrequest =~ s/{TIMESTAMP}/$timestamp/g;}  
            $logresponse = $xmltestcases->{case}->{$testnum}->{logresponse}; if ($logresponse) {$logresponse =~ s/{AMPERSAND}/&/g; $logresponse =~ s/{TIMESTAMP}/$timestamp/g;}  
                         
            print RESULTS "<b>Test:  $currentcasefile - $testnum </b><br>\n";
            if ($description1) {print RESULTS "$description1 <br>\n";}
            if ($description2) {print RESULTS "$description2 <br>\n";}
            print RESULTS "<br>\n";
            if ($verifypositive) {print RESULTS "Verify: \"$verifypositive\" <br> \n";}
            if ($verifynegative) {print RESULTS "Verify Negative: \"$verifynegative\" <br> \n";}
            if ($verifypositivenext) {print RESULTS "Verify On Next Case: \"$verifypositivenext\" <br> \n";}
            if ($verifynegativenext) {print RESULTS "Verify Negative On Next Case: \"$verifynegativenext\" <br> \n";}
            
            if($method)
            {
                if ($method eq "get")
                {   httpget();  }
                elsif ($method eq "post")
                {   httppost(); }
                else {print STDERR qq|ERROR: bad HTTP Request Method Type, you must use "get" or "post"\n|;}
                }
            else
            {   
                httpget(); #use "get" if no method is specified  
            }  
                
            verify();  #verify result from http response
            
            print RESULTS "Response Time = $latency s<br>\n";
            print RESULTS "<br>\n-------------------------------------------------------<br>\n\n";
                        
            $testnum++;
            $totalruncount++;
        }       
    }
    


    $endruntimer = time();
    $totalruntime = (int(10 * ($endruntimer - $startruntimer)) / 10);  #elapsed time rounded to thousandths 

    $out_window->insert("end", "Execution Finished... see results.html file for detailed output"); $out_window->see("end");
    
    $status_window->insert("end", "\n\n------------------------------\nTotal Run Time: $totalruntime  seconds\n");
    $status_window->insert("end", "\nTest Cases Run: $totalruncount\nVerifications Passed: $passedcount\nVerifications Failed: $failedcount\n"); 
    $status_window->see("end");

    writefinalhtml();
    
    close(RESULTS);
    close(HTTPLOGFILE);
    
    $rtc_button->configure(-state       => 'normal',  #re-enable button after finish
                           -background  => '#EFEFEF',
                           );


}



#------------------------------------------------------------------
#  SUBROUTINES
#------------------------------------------------------------------
sub writeinitialhtml {

    print RESULTS 
qq(    
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
); 
}
#------------------------------------------------------------------
sub writefinalhtml {

    print RESULTS
qq(    
<br><hr><br>
<b>
Start Time: $currentdatetime <br>
Total Run Time: $totalruntime  seconds <br>
<br>
Test Cases Run: $totalruncount <br>
Verifications Passed: $passedcount <br>
Verifications Failed: $failedcount <br>
</b>
<br>

</body>
</html>
); 
}
#------------------------------------------------------------------
sub httpget {  #send http request and read response
        
    $request = new HTTP::Request('GET',"$url");

    $cookie_jar->add_cookie_header($request);
    
    $starttimer = time();
    $response = $useragent->simple_request($request);
    $endtimer = time();
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  #elapsed time rounded to thousandths 
      
    if ($logrequest && $logrequest eq "yes") {print HTTPLOGFILE $request->as_string; print HTTPLOGFILE "\n\n";} 
    if ($logresponse && $logresponse eq "yes") {print HTTPLOGFILE $request->as_string; print HTTPLOGFILE "\n\n";} 
    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n";
}
#------------------------------------------------------------------
sub httppost {  #send http request and read response
    
    $request = new HTTP::Request('POST',"$url");
    $request->content_type('application/x-www-form-urlencoded\n\n');
    $request->content($postbody);
    #print $request->as_string; print "\n\n";
    $cookie_jar->add_cookie_header($request);
    
    $starttimer = time();
    $response = $useragent->simple_request($request);
    $endtimer = time();
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  #elapsed time rounded to thousandths 
     
    if ($logrequest && $logrequest eq "yes") {print HTTPLOGFILE $request->as_string; print HTTPLOGFILE "\n\n";} 
    if ($logresponse && $logresponse eq "yes") {print HTTPLOGFILE $request->as_string; print HTTPLOGFILE "\n\n";} 
    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n";
}
#------------------------------------------------------------------
sub verify {  #do verification of http response and print PASSED/FAILED to report and UI

    if ($verifypositive)
    {
        if ($response->as_string() =~ /$verifypositive/i)  #verify existence of string in response
        {
            print RESULTS "<b><font color=green>PASSED</font></b><br>\n";
            $status_window->insert("end", "PASSED\n"); $status_window->see("end");
            $passedcount++;
        }
        else
        {
            print RESULTS "<b><font color=red>FAILED</font></b><br>\n";
            $status_window->insert("end", "FAILED\n"); $status_window->see("end");            
            $failedcount++;                
        }
    }



    if ($verifynegative)
    {
        if ($response->as_string() =~ /$verifynegative/i)  #verify existence of string in response
        {
            print RESULTS "<b><font color=red>FAILED</font></b><br>\n";
            $status_window->insert("end", "FAILED\n"); $status_window->see("end");            
            $failedcount++;  
        }
        else
        {
            print RESULTS "<b><font color=green>PASSED</font></b><br>\n";
            $status_window->insert("end", "PASSED\n"); $status_window->see("end");
            $passedcount++;                
        }
    }


    
    if ($verifylater)
    {
        if ($response->as_string() =~ /$verifylater/i)  #verify existence of string in response
        {
            print RESULTS "<b><font color=green>PASSED</font></b> (verification set in previous test case)<br>\n";
            $status_window->insert("end", "PASSED\n"); $status_window->see("end");
            $passedcount++;
        }
        else
        {
            print RESULTS "<b><font color=red>FAILED</font></b> (verification set in previous test case)<br>\n";
            $status_window->insert("end", "FAILED\n"); $status_window->see("end");            
            $failedcount++;                
        }
        
        $verifylater = '';  #set to null after verification
    }
    
    
    
    if ($verifylaterneg)
    {
        if ($response->as_string() =~ /$verifylaterneg/i)  #verify existence of string in response
        {
            print RESULTS "<b><font color=red>FAILED</font></b> (negative verification set in previous test case)<br>\n";
            $status_window->insert("end", "FAILED\n"); $status_window->see("end");            
            $failedcount++;  
        }
        else
        {
            print RESULTS "<b><font color=green>PASSED</font></b> (negative verification set in previous test case)<br>\n";
            $status_window->insert("end", "PASSED\n"); $status_window->see("end");
            $passedcount++;                   
        }
        
        $verifylaterneg = '';  #set to null after verification
    }



    #verify http response code is in the 100-399 range    
    if ($response->as_string() =~ /HTTP\/1.(0|1) (1|2|3)/i)  #verify existance of string in response
    {
        #don't print anything for succesful response codes (100-399) 
    }
    else
    {
        print RESULTS "<b><font color=red>FAILED</font></b>";
        $response->as_string() =~ /(HTTP\/1.)(.*)/i;
        print RESULTS " ($1$2)<br>\n";  #print http response code to report if failed
        $status_window->insert("end", "FAILED ($1$2)\n"); $status_window->see("end");            
        $failedcount++;            
    }
        
}
#------------------------------------------------------------------
sub convtestcases {  #convert ampersands in test cases to {AMPERSAND} so xml parser doesn't puke
#this is a riduclous kluge but works

    open(XMLTOCONVERT, "$currentcasefile") || die "\nError: Failed to open test case file\n\n";  #open file handle   
    @xmltoconvert = <XMLTOCONVERT>;  #Read the file into an array
    
    $casecount = 0;
    
    foreach (@xmltoconvert)
    { 
        s/&/{AMPERSAND}/g;  #convert ampersands (&) &'s are malformed XML
        
        if ($_ =~ /<case/) #count test cases based on '<case' tag
        {
            $casecount++; 
        }    
    }  

    close(XMLTOCONVERT);   


    open(XMLTOCONVERT, ">$currentcasefile") || die "\nERROR: Failed to open test case file\n\n";  #open file handle   
    print XMLTOCONVERT @xmltoconvert; #overwrite file with converted array
    close(XMLTOCONVERT);
}
#------------------------------------------------------------------
sub processconfigfile {  #get test case files to run and evaluate constants
    
    undef @casefilelist; #empty the array
    
    open(CONFIG, "config.xml") || die "\nERROR: Failed to open config.xml file\n\n";  #open file handle   
    @configfile = <CONFIG>;  #Read the file into an array

    #parse test case file names from config.xml and build array
    foreach (@configfile)
    {
        if (/<testcasefile>/)
        {   
            $firstparse = $';  #print "$' \n\n";
            $firstparse =~ /<\/testcasefile>/;
            $filename = $`;  #string between tags will be in $filename
            #print "$filename \n\n";
            push @casefilelist, $filename;  #add next filename we grab to end of array
        }
    }    
    
    if ($casefilelist[0])
    {
    }
    else
    {
        push @casefilelist, "testcases.xml";  #if no file specified in config.xml, default to testcases.xml
    }
    
    #print "testcase file list: @casefilelist\n\n";
    
    #grab value for constant: baseurl
    foreach (@configfile)
    {
        if (/<baseurl>/)
        {   
            $firstparse = $';  #print "$' \n\n";
            $firstparse =~ /<\/baseurl>/;
            $baseurl = $`;  #string between tags will be in $baseurl
            #print "$baseurl \n\n";
        }
    }  
    
    close(CONFIG);
}
#------------------------------------------------------------------
