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
use Data::Dumper;   

$| = 1; #don't buffer output to STDOUT

    $startruntimer = time();  #timer for entire test run
    
    $currentdatetime = localtime time;  #get current date and time for results report

    print "\nWebInject is running ...  see results.html file for output \n\n\n";

    open(HTTPLOGFILE, ">http.log") || die "Failed to open http.log file\n";   

    open(RESULTS, ">results.html") || die "Failed to open results.html file\n";    
      
    writeinitialhtml();
       
    configtestcasefiles();
    
    #contsruct objects
    $useragent = LWP::UserAgent->new;
    $cookie_jar = HTTP::Cookies->new;

    $totalruncount = 0;
    $passedcount = 0;
    $failedcount = 0;
    
    
    foreach (@casefilelist) #process test case files named in config.xml
    {
        $currentcasefile = $_;
        #print "$currentcasefile\n\n";
        
        $testnum = 1;
        
        convtestcases();
        
        $xmltestcases = XMLin("./$currentcasefile"); #slurp test case file to parse
        #print Dumper($xmltestcases);  #for debug, dump hash of xml   
        #print keys %{$configfile};  #print keys from dereferenced hash
        
        print "completed preprocessing test case file:\n$currentcasefile\nbeginning execution \n";
     
     
        #special handling for when only one test case exists (hash is referenced different than with multiples due to how the parser formats the hash)
        if ($casecount == 1){  
        
            #populate variables with values from testcase file and revert {AMPERSAND} back to "&"
            $description1 = $xmltestcases->{case}->{description1}; if ($description1) {$description1 =~ s/{AMPERSAND}/&/g;}
            $description2 = $xmltestcases->{case}->{description2}; if ($description2) {$description2 =~ s/{AMPERSAND}/&/g;}
            $method = $xmltestcases->{case}->{method}; if ($method) {$method =~ s/{AMPERSAND}/&/g;}
            $url = $xmltestcases->{case}->{url}; if ($url) {$url =~ s/{AMPERSAND}/&/g;}
            $postbody = $xmltestcases->{case}->{postbody}; if ($postbody) {$postbody =~ s/{AMPERSAND}/&/g;}
            $verifypositive = $xmltestcases->{case}->{verifypositive}; if ($verifypositive) {$verifypositive =~ s/{AMPERSAND}/&/g;}
            $verifynegative = $xmltestcases->{case}->{verifynegative}; if ($verifynegative) {$verifynegative =~ s/{AMPERSAND}/&/g;}
            $logrequest = $xmltestcases->{case}->{logrequest}; if ($logrequest) {$logrequest =~ s/{AMPERSAND}/&/g;}
            $logresponse = $xmltestcases->{case}->{logresponse}; if ($logresponse) {$logresponse =~ s/{AMPERSAND}/&/g;}
            
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
                    else {print qq|ERROR: bad HTTP Request Method Type, you must use "get" or "post"\n|;}
                }
            else
                {   
                    httpget();  #use "get" if no method is specified 
                }  
                
            verify();  #verify result from http response
            
            print RESULTS "Response Time = $latency s<br>\n";
            print RESULTS "<br>\n-------------------------------------------------------<br>\n\n";
            
            $testnum++;
            $totalruncount++;
        }
        
        
        while ($testnum <= $casecount){  #make any changes here to special case above
            print " .";
            #populate variables with values from testcase file and revert {AMPERSAND} back to "&"
            $description1 = $xmltestcases->{case}->{$testnum}->{description1}; if ($description1) {$description1 =~ s/{AMPERSAND}/&/g;}
            $description2 = $xmltestcases->{case}->{$testnum}->{description2}; if ($description2) {$description2 =~ s/{AMPERSAND}/&/g;}
            $method = $xmltestcases->{case}->{$testnum}->{method}; if ($method) {$method =~ s/{AMPERSAND}/&/g;}
            $url = $xmltestcases->{case}->{$testnum}->{url}; if ($url) {$url =~ s/{AMPERSAND}/&/g;}
            $postbody = $xmltestcases->{case}->{$testnum}->{postbody}; if ($postbody) {$postbody =~ s/{AMPERSAND}/&/g;}
            $verifypositive = $xmltestcases->{case}->{$testnum}->{verifypositive}; if ($verifypositive) {$verifypositive =~ s/{AMPERSAND}/&/g;}
            $verifynegative = $xmltestcases->{case}->{$testnum}->{verifynegative}; if ($verifynegative) {$verifynegative =~ s/{AMPERSAND}/&/g;}
            $logrequest = $xmltestcases->{case}->{$testnum}->{logrequest}; if ($logrequest) {$logrequest =~ s/{AMPERSAND}/&/g;}
            $logresponse = $xmltestcases->{case}->{$testnum}->{logresponse}; if ($logresponse) {$logresponse =~ s/{AMPERSAND}/&/g;}
            
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
                    else {print qq|ERROR: bad HTTP Request Method Type, you must use "get" or "post"\n|;}
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
        
        print "\n";
    }
    
    
    print "\n\nexecution completed\n\n";

    $endruntimer = time();
    $totalruntime = (int(10 * ($endruntimer - $startruntimer)) / 10);  #elapsed time rounded to thousandths 

    writefinalhtml();
    
    close(RESULTS);
    close(HTTPLOGFILE);




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
    if ($logresponse && $logresponse eq "yes") {print HTTPLOGFILE $response->as_string; print HTTPLOGFILE "\n\n";} 
    $cookie_jar->extract_cookies($response);
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
    if ($logresponse && $logresponse eq "yes") {print HTTPLOGFILE $response->as_string; print HTTPLOGFILE "\n\n";} 
    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n"; 
}
#------------------------------------------------------------------

sub verify {  #do verification of http response

    if ($verifypositive)
        {
        if ($response->as_string() =~ /$verifypositive/i)  #verify existance of string in response
            {
            print RESULTS "<b><font color=green>PASSED</font></b><br>\n";
            $passedcount++;
            }
        else
            {
            print RESULTS "<b><font color=red>FAILED</font></b><br>\n"; 
            $failedcount++;                
            }
        }
        
        
    if ($verifynegative)
        {
        if ($response->as_string() =~ /$verifynegative/i)  #verify existance of string in response
            {
            print RESULTS "<b><font color=red>FAILED</font></b><br>\n"; 
            $failedcount++;  
            }
        else
            {
            print RESULTS "<b><font color=green>PASSED</font></b><br>\n";
            $passedcount++;                
            }
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
        $failedcount++;            
        }
        
}
#------------------------------------------------------------------
sub convtestcases {  #convert ampersands in test cases to {AMPERSAND} so xml parser doesn't puke
#this is a riduclous kluge but works

    open(XMLTOCONVERT, "$currentcasefile") || die "\nFailed to open test case file\n";  #open file handle   
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


    open(XMLTOCONVERT, ">$currentcasefile") || die "\nFailed to open test case file\n";  #open file handle   
    print XMLTOCONVERT @xmltoconvert; #overwrite file with converted array
    close(XMLTOCONVERT);
}
#------------------------------------------------------------------
sub configtestcasefiles {  #parse test case file names from config.xml and build array

    open(CONFIG, "config.xml") || die "\nFailed to open config.xml file\n";  #open file handle   
    @configfile = <CONFIG>;  #Read the file into an array

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
    close(CONFIG);
}
#------------------------------------------------------------------
