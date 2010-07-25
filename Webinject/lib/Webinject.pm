package Webinject;

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

use 5.006;
use strict;
use warnings;
use Carp;
use LWP;
use HTTP::Request::Common;
use HTTP::Cookies;
use XML::Simple;
use Time::HiRes 'time', 'sleep';
use Getopt::Long;
use Crypt::SSLeay;              # for SSL/HTTPS (you may comment this out if you don't need it)
use XML::Parser;                # for web services verification (you may comment this out if aren't doing XML verifications for web services)
use Error qw(:try);             # for web services verification (you may comment this out if aren't doing XML verifications for web services)
use Data::Dumper;               # dump hashes for debugging
use File::Temp qw/ tempfile /;  # create temp files

our $VERSION = '1.50';

=head1 NAME

Webinject - Perl Module for testing web services

=head1 SYNOPSIS

    use Webinject;
    my $webinject = Webinject->new();
    $webinject->engine();

=head1 DESCRIPTION

WebInject is a free tool for automated testing of web applications and web
services. It can be used to test individual system components that have HTTP
interfaces (JSP, ASP, CGI, PHP, AJAX, Servlets, HTML Forms, XML/SOAP Web
Services, REST, etc), and can be used as a test harness to create a suite of
[HTTP level] automated functional, acceptance, and regression tests. A test
harness allows you to run many test cases and collect/report your results.
WebInject offers real-time results display and may also be used for monitoring
system response times.

=head1 CONSTRUCTOR

=head2 new ( [ARGS] )

Creates an C<Webinject> object.

=cut

sub new {
    my $class     = shift;
    my (%options) = @_;
    $|            = 1;     # don't buffer output to STDOUT
    my $self      = {};

    for my $opt_key ( keys %options ) {
        if ( exists $self->{$opt_key} ) {
            $self->{$opt_key} = $options{$opt_key};
        }
        else {
            croak("unknown option: $opt_key");
        }
    }

    bless $self, $class;

    $self->_set_defaults();

    return $self;
}

########################################

=head1 METHODS

=head2 engine

start the engine of webinject

=cut

sub engine {
    #wrap the whole engine in a subroutine so it can be integrated with the gui
    my $self = shift;

    my ($startruntimer, $endruntimer);
    my ($curgraphtype);
    my ($xmltestcases);

    # undef local values
    map { $self->{'case'}->{$_} = undef } qw/method description1 description2 sleep/;

    if( $self->{'gui'} ) { $self->_gui_initial(); }

    $self->_getdirname();       # get the directory webinject engine is running from
    $self->_whackoldfiles();    # delete files leftover from previous run (do this here so they are whacked each run)

    #construct objects
    $self->{'useragent'}  = LWP::UserAgent->new;
    $self->{'cookie_jar'} = HTTP::Cookies->new;
    $self->{'useragent'}->agent('WebInject');    # http useragent that will show up in webserver logs
    $self->{'useragent'}->max_redirect('0');     # don't follow redirects for GET's (POST's already don't follow, by default)

    if(!defined $self->{'gui'}) {
        $self->{'config'}->{standaloneplot} = 'off'; # initialize so we don't get warnings when <standaloneplot> is not set in config
    }

    $self->_processcasefile();

    # add proxy support if it is set in config.xml
    if( $self->{'config'}->{proxy} ) {
        $self->{'useragent'}->proxy( [ 'http', 'https' ], $self->{'config'}->{proxy} );
    }

    # add http basic authentication support
    # corresponds to:
    # $self->{'useragent'}->credentials('servername:portnumber', 'realm-name', 'username' => 'password');
    if( scalar @{ $self->{'config'}->{'httpauth'} } ) {

        # add the credentials to the user agent here. The foreach gives the reference to the tuple ($elem), and we
        # deref $elem to get the array elements.
        for my $elem ( @{ $self->{'config'}->{'httpauth'} } ) {
            #print "adding credential: $elem->[0]:$elem->[1], $elem->[2], $elem->[3] => $elem->[4]\n";
            $self->{'useragent'}->credentials( $elem->[0].":".$elem->[1], $elem->[2], $elem->[3] => $elem->[4] );
        }
    }

    # change response delay timeout in seconds if it is set in config.xml
    if($self->{'config'}->{timeout}) {
        $self->{'useragent'}->timeout($self->{'config'}->{timeout});    #default LWP timeout is 180 secs.
    }

    #open file handles
    unless( $self->{'config'}->{'reporttype'} ) {           # we suppress most logging when running in a plugin mode
        if( $self->{'opt_output'} ) {           # use output location if it is passed from the command line
            open( $self->{'HTTPLOGFILE'}, ">", $self->{'opt_output'}."http.log" )
              or die "\nERROR: Failed to open http.log file: $!\n\n";
            open( $self->{'RESULTS'}, ">", $self->{'opt_output'}."results.html" )
              or die "\nERROR: Failed to open results.html file: $!\n\n";
            open( $self->{'RESULTSXML'}, ">", $self->{'opt_output'}."results.xml" )
              or die "\nERROR: Failed to open results.xml file: $!\n\n";
        }
        else {
            open( $self->{'HTTPLOGFILE'}, ">", $self->{'dirname'}."http.log" )
              or die "\nERROR: Failed to open http.log file\n\n";
            open( $self->{'RESULTS'}, ">", $self->{'dirname'}."results.html" )
              or die "\nERROR: Failed to open results.html file\n\n";
            open( $self->{'RESULTSXML'}, ">", $self->{'dirname'} . "results.xml" )
              or die "\nERROR: Failed to open results.xml file\n\n";
        }
    }

    my $results    = $self->{'RESULTS'};
    my $resultsxml = $self->{'RESULTSXML'};
    unless( $self->{'config'}->{'reporttype'} ) {           # we suppress most logging when running in a plugin mode
        print $resultsxml qq|<results>\n\n|;    # write initial xml tag
        $self->_writeinitialhtml();             # write opening tags for results file
    }

    unless( $self->{'xnode'} or $self->{'nooutput'} ) { # skip regular STDOUT output if using an XPath or $self->{'nooutput'} is set
        $self->_writeinitialstdout();                   # write opening tags for STDOUT.
    }

    # set the initial value so we know if the user changes the graph setting from the gui
    if($self->{'gui'}) {
        $curgraphtype = $self->{'config'}->{'graphtype'};
    }

    $self->_gnuplotcfg();    #create the gnuplot config file

    $self->{'totalruncount'}         = 0;
    $self->{'case'}->{'passedcount'} = 0;
    $self->{'case'}->{'failedcount'} = 0;
    $self->{'passedcount'}           = 0;
    $self->{'failedcount'}           = 0;
    $self->{'totalresponse'}         = 0;
    $self->{'avgresponse'}           = 0;
    $self->{'maxresponse'}           = 0;
    $self->{'minresponse'}           = 10000000;    #set to large value so first minresponse will be less
    $self->{'stop'}                  = 'no';
    $self->{'plotclear'}             = 'no';

    $startruntimer = time();    #timer for entire test run

    for my $currentcasefile ( @{ $self->{'casefilelist'} } ) { #process test case files named in config
        #print "\n$currentcasefile\n\n";

        $self->{'case'}->{'filecheck'} = ' ';

        if($self->{'gui'}) { $self->_gui_processing_msg(); }

        my $tempfile = $self->_convtestcases($currentcasefile);

        $xmltestcases = XMLin( $tempfile, VarAttr => 'varname' );    # slurp test case file to parse (and specify variables tag)
        # fix case if there is only one case
        if( defined $xmltestcases->{'case'}->{'id'} ) {
            my $tmpcase = $xmltestcases->{'case'};
            $xmltestcases->{'case'} = { $tmpcase->{'id'} => $tmpcase };
        }
        #print Dumper($xmltestcases);  #for debug, dump hash of xml
        #print keys %{$self->{'config'}->file};  #for debug, print keys from dereferenced hash

        #delete the temp file as soon as we are done reading it
        if ( -e $tempfile ) { unlink $tempfile; }

        my $repeat = 1;
        if(defined $xmltestcases->{repeat}) {
            $repeat = $xmltestcases->{repeat};
        }
        
        $self->{'result'} = [];
        for my $run_nr (1 .. $repeat) {

            $self->{'runcount'} = 0;

            # process cases in sorted order
            for my $testnum ( sort { $a <=> $b } keys %{ $xmltestcases->{case} } ) {

                # if an XPath Node is defined, only process the single Node
                if( $self->{'xnode'} ) {
                    $testnum = $self->{'xnode'};
                }

                $self->{'isfailure'} = 0;

                if( $self->{'gui'} ) {
                    # don't do this if monitor is disabled in gui
                    unless( $self->{'monitorenabledchkbx'} eq 'monitor_off' ) {
                        # check to see if the user changed the graph setting
                        if(!defined $curgraphtype or $curgraphtype ne $self->{'config'}->{'graphtype'} ) {
                            $self->_gnuplotcfg(); # create the gnuplot config file since graph setting changed
                            $curgraphtype = $self->{'config'}->{'graphtype'};
                        }
                    }
                }

                # used to replace parsed {timestamp} with real timestamp value
                my $timestamp = time();

                # grab $self->{'case'}->{verifypositivenext} string from previous test case (if it exists)
                if( $self->{'case'}->{verifypositivenext} ) {
                    $self->{'verifylater'} = $self->{'case'}->{verifypositivenext};
                }
                # grab $self->{'case'}->{verifynegativenext} string from previous test case (if it exists)
                if( $self->{'case'}->{verifynegativenext} ) {
                    $self->{'verifylaterneg'} =
                      $self->{'case'}->{verifynegativenext};
                }

                # populate variables with values from testcase file, do substitutions, and revert converted values back
                for (
                    qw/method description1 description2 url postbody posttype addheader
                    verifypositive verifypositive1 verifypositive2 verifypositive3
                    verifynegative verifynegative1 verifynegative2 verifynegative3
                    parseresponse parseresponse1 parseresponse2 parseresponse3 parseresponse4 parseresponse5
                    verifyresponsecode logrequest logresponse sleep errormessage
                    verifypositivenext verifynegativenext/
                  )
                {
                    $self->{'case'}->{$_} = $xmltestcases->{case}->{$testnum}->{$_};
                    if( defined $self->{'case'}->{$_} ) {
                        $self->{'case'}->{$_} = $self->_convertbackxml( $self->{'case'}->{$_}, $timestamp );
                    }
                }

                if( $self->{'gui'} ) { $self->_gui_tc_descript(); }

                unless( $self->{'config'}->{'reporttype'} ) {
                    # we suppress most logging when running in a plugin mode
                    print $results qq|<b>Test:  $currentcasefile - $testnum </b><br />\n|;
                }

                unless( $self->{'nooutput'} ) {    #skip regular STDOUT output
                    print STDOUT qq|Test:  $currentcasefile - $testnum \n|;
                }

                unless( $self->{'config'}->{'reporttype'} ) {    #we suppress most logging when running in a plugin mode
                    unless( $self->{'case'}->{'filecheck'} eq $currentcasefile ) {
                        # if this is the first test case file, skip printing the closing tag for the previous one
                        unless ( $currentcasefile eq $self->{'casefilelist'}->[0] ) {
                            print $resultsxml qq|    </testcases>\n\n|;
                        }
                        print $resultsxml qq|    <testcases file="$currentcasefile">\n\n|;
                    }
                    print $resultsxml qq|        <testcase id="$testnum">\n|;
                }

                for(qw/description1 description2/) {
                    next unless defined $self->{'case'}->{$_};
                    unless ( $self->{'config'}->{'reporttype'} ) {    #we suppress most logging when running in a plugin mode
                        print $results qq|$self->{'case'}->{$_} <br />\n|;
                        unless ( $self->{'nooutput'} ) {    #skip regular STDOUT output
                            print STDOUT qq|$self->{'case'}->{$_} \n|;
                        }
                        print $resultsxml qq|            <$_>$self->{'case'}->{$_}</$_>\n|;
                    }
                }

                unless( $self->{'config'}->{'reporttype'} ) {    #we suppress most logging when running in a plugin mode
                    print $results qq|<br />\n|;
                }

                for (
                    qw/verifypositive verifypositive1 verifypositive2 verifypositive3
                    verifynegative verifynegative1 verifynegative2 verifynegative3/
                  )
                {
                    my $negative = $_ =~ /negative/mx ? "Negative" : "";
                    if( $self->{'case'}->{$_} ) {
                        unless ( $self->{'config'}->{'reporttype'} ) { #we suppress most logging when running in a plugin mode
                            print $results qq|Verify $negative: "$self->{'case'}->{$_}" <br />\n|;
                            unless ( $self->{'nooutput'} ) {    #skip regular STDOUT output
                                print STDOUT qq|Verify $negative: "$self->{'case'}->{$_}" \n|;
                            }
                            print $resultsxml qq|            <$_>$self->{'case'}->{$_}</$_>\n|;
                        }
                    }
                }

                if( $self->{'case'}->{verifypositivenext} ) {
                    unless( $self->{'config'}->{'reporttype'} ) {    #we suppress most logging when running in a plugin mode
                        print $results qq|Verify On Next Case: "$self->{'case'}->{verifypositivenext}" <br />\n|;
                        unless ( $self->{'nooutput'} ) {    #skip regular STDOUT output
                            print STDOUT qq|Verify On Next Case: "$self->{'case'}->{verifypositivenext}" \n|;
                        }
                        print $resultsxml qq|            <verifypositivenext>$self->{'case'}->{verifypositivenext}</verifypositivenext>\n|;
                    }
                }

                if( $self->{'case'}->{verifynegativenext} ) {
                    unless( $self->{'config'}->{'reporttype'} ) {    #we suppress most logging when running in a plugin mode
                        print $results qq|Verify Negative On Next Case: "$self->{'case'}->{verifynegativenext}" <br />\n|;
                        unless ( $self->{'nooutput'} ) {    #skip regular STDOUT output
                            print STDOUT qq|Verify Negative On Next Case: "$self->{'case'}->{verifynegativenext}" \n|;
                        }
                        print $resultsxml qq|            <verifynegativenext>$self->{'case'}->{verifynegativenext}</verifynegativenext>\n|;
                    }
                }

                if( $self->{'case'}->{verifyresponsecode} ) {
                    unless( $self->{'config'}->{'reporttype'} ) {    #we suppress most logging when running in a plugin mode
                        print $results qq|Verify Response Code: "$self->{'case'}->{verifyresponsecode}" <br />\n|;
                        unless ( $self->{'nooutput'} ) {    #skip regular STDOUT output
                            print STDOUT qq|Verify Response Code: "$self->{'case'}->{verifyresponsecode}" \n|;
                        }
                        print $resultsxml qq|            <verifyresponsecode>$self->{'case'}->{verifyresponsecode}</verifyresponsecode>\n|;
                    }
                }

                my($latency,$request);
                if( $self->{'case'}->{method} ) {
                    if ( $self->{'case'}->{method} eq "get" ) {
                        ($latency,$request) = $self->_httpget();
                    }
                    elsif ( $self->{'case'}->{method} eq "post" ) {
                        ($latency,$request) = $self->_httppost();
                    }
                    else {
                        print STDERR qq|ERROR: bad HTTP Request Method Type, you must use "get" or "post"\n|;
                    }
                }
                else {
                    ($latency,$request) = $self->_httpget();       # use "get" if no method is specified
                }

                $self->_verify();                       # verify result from http response
                $self->_httplog($request);              # write to http.log file
                $self->_plotlog($latency);              # send perf data to log file for plotting
                $self->_plotit();                       # call the external plotter to create a graph

                if( $self->{'gui'} ) {
                    $self->_gui_updatemontab(); # update monitor with the newly rendered plot graph
                }

                $self->_parseresponse();                # grab string from response to send later

                if( $self->{'isfailure'} > 0 ) {       # if any verification fails, test case is considered a failure
                    unless ( $self->{'config'}->{'reporttype'} ) {  # we suppress most logging when running in a plugin mode
                        print $resultsxml qq|            <success>false</success>\n|;
                    }
                    if( $self->{'case'}->{errormessage} ) {    # Add defined error message to the output
                        unless ( $self->{'config'}->{'reporttype'} ) {      # we suppress most logging when running in a plugin mode
                            print $results qq|<b><span class="fail">TEST CASE FAILED : $self->{'case'}->{errormessage}</span></b><br />\n|;
                            print $resultsxml qq|            <result-message>$self->{'case'}->{errormessage}</result-message>\n|;
                        }
                        unless( $self->{'nooutput'} ) {    #skip regular STDOUT output
                            print STDOUT qq|TEST CASE FAILED : $self->{'case'}->{errormessage}\n|;
                        }
                    }
                    else {    #print regular error output
                        unless ( $self->{'config'}->{'reporttype'} ) { #we suppress most logging when running in a plugin mode
                            print $results qq|<b><span class="fail">TEST CASE FAILED</span></b><br />\n|;
                            print $resultsxml qq|            <result-message>TEST CASE FAILED</result-message>\n|;
                        }
                        unless( $self->{'nooutput'} ) {    #skip regular STDOUT output
                            print STDOUT qq|TEST CASE FAILED\n|;
                        }
                    }
                    unless( $self->{'returnmessage'} ) { #(used for plugin compatibility) if it's the first error message, set it to variable
                        if ( $self->{'case'}->{errormessage} ) {
                            $self->{'returnmessage'} = $self->{'case'}->{errormessage};
                        }
                        else {
                            $self->{'returnmessage'} = "Test case number $testnum failed";
                        }

                        #print "\nReturn Message : $self->{'returnmessage'}\n"
                    }
                    if( $self->{'gui'} ) {
                        $self->_gui_status_failed();
                    }
                    $self->{'case'}->{'failedcount'}++;
                }
                else {
                    unless ( $self->{'config'}->{'reporttype'} ) {    #we suppress most logging when running in a plugin mode
                        print $results qq|<b><span class="pass">TEST CASE PASSED</span></b><br />\n|;
                    }
                    unless ( $self->{'nooutput'} ) { #skip regular STDOUT output
                        print STDOUT qq|TEST CASE PASSED \n|;
                    }
                    unless ( $self->{'config'}->{'reporttype'} ) {    #we suppress most logging when running in a plugin mode
                        print $resultsxml qq|            <success>true</success>\n|;
                        print $resultsxml qq|            <result-message>TEST CASE PASSED</result-message>\n|;
                    }
                    if( $self->{'gui'} ) {
                        $self->_gui_status_passed();
                    }
                    $self->{'case'}->{'passedcount'}++;
                }

                unless( $self->{'config'}->{'reporttype'} ) {    #we suppress most logging when running in a plugin mode
                    print $results qq|Response Time = $latency sec <br />\n|;
                }

                if( $self->{'gui'} ) { $self->_gui_timer_output(); }

                unless( $self->{'nooutput'} ) {    #skip regular STDOUT output
                    print STDOUT qq|Response Time = $latency sec \n|;
                }

                unless( $self->{'config'}->{'reporttype'} ) {    #we suppress most logging when running in a plugin mode
                    print $resultsxml qq|            <responsetime>$latency</responsetime>\n|;
                    print $resultsxml qq|        </testcase>\n\n|;
                    print $results qq|<br />\n------------------------------------------------------- <br />\n\n|;
                }

                unless( $self->{'xnode'} or $self->{'nooutput'} ) { #skip regular STDOUT output if using an XPath or $self->{'nooutput'} is set
                    print STDOUT qq|------------------------------------------------------- \n|;
                }

                $self->{'case'}->{'filecheck'} = $currentcasefile ; #set this so <testcases> xml is only closed after each file is done processing

                $endruntimer = time();
                $self->{'totalruntime'} = ( int( 1000 * ( $endruntimer - $startruntimer ) ) / 1000 );    #elapsed time rounded to thousandths

                $self->{'runcount'}++;
                $self->{'totalruncount'}++;

                if( $self->{'gui'} ) {
                    $self->_gui_statusbar();    #update the statusbar
                }

                if( $latency > $self->{'maxresponse'} ) {
                    $self->{'maxresponse'} = $latency; # set max response time
                }
                if( $latency < $self->{'minresponse'} ) {
                    $self->{'minresponse'} = $latency; # set min response time
                }
                # keep total of response times for calculating avg
                $self->{'totalresponse'} = ( $self->{'totalresponse'} + $latency );
                # avg response rounded to thousandths
                $self->{'avgresponse'} = ( int( 1000 * ( $self->{'totalresponse'} / $self->{'totalruncount'} ) ) / 1000 );
                
                push @{$self->{'result'}}, {
                    'label'   => $run_nr,
                    'latency' => $latency,
                };

                if( $self->{'gui'} ) {
                    $self->_gui_updatemonstats(); # update timers and counts in monitor tab
                }

                # break from sub if user presses stop button in gui
                if( $self->{'stop'} eq 'yes' ) {
                    $self->_finaltasks();
                    $self->{'stop'} = 'no';
                    return;    # break from sub
                }

                # if a sleep value is set in the test case, sleep that amount
                if( $self->{'case'}->{sleep} ) {
                    sleep( $self->{'case'}->{sleep} );
                }
                

                # if an XPath Node is defined, only process the single Node
                if( $self->{'xnode'} ) {
                    last;
                }
            }
        }
    }

    $self->_finaltasks();    # do return/cleanup tasks

    return;
}

################################################################################
# set defaults
sub _set_defaults {
    my $self = shift;
    $self->{'currentdatetime'}  = localtime time;    #get current date and time for results report
    $self->{config}             = {
        'graphtype'                 => 'lines',
        'httpauth'                  => [],
    };
    $self->{exit_codes}         = {
        'UNKNOWN'  => 3,
        'OK'       => 0,
        'WARNING'  => 1,
        'CRITICAL' => 2,
    };
    $self->_getoptions(); # get command line options
    return;
}

################################################################################
# write opening tags for results file
sub _writeinitialhtml {
    my $self    = shift;
    my $results = $self->{'RESULTS'};

    print $results
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
    return;
}

################################################################################
# write initial text for STDOUT
sub _writeinitialstdout {
    my $self = shift;

    print STDOUT qq|
Starting WebInject Engine...

-------------------------------------------------------
|;
    return;
}

################################################################################
# write summary and closing tags for results file
sub _writefinalhtml {
    my $self    = shift;
    my $results = $self->{'RESULTS'};

    print $results qq|
<br /><hr /><br />
<b>
Start Time: $self->{'currentdatetime'} <br />
Total Run Time: $self->{'totalruntime'} seconds <br />
<br />
Test Cases Run: $self->{'totalruncount'} <br />
Test Cases Passed: $self->{'case'}->{'passedcount'} <br />
Test Cases Failed: $self->{'case'}->{'failedcount'} <br />
Verifications Passed: $self->{'passedcount'} <br />
Verifications Failed: $self->{'failedcount'} <br />
<br />
Average Response Time: $self->{'avgresponse'} seconds <br />
Max Response Time: $self->{'maxresponse'} seconds <br />
Min Response Time: $self->{'minresponse'} seconds <br />
</b>
<br />

</body>
</html>
|;
    return;
}

################################################################################
# write summary and closing tags for XML results file
sub _writefinalxml {
    my $self       = shift;
    my $resultsxml = $self->{'RESULTSXML'};

    print $resultsxml qq|
    </testcases>

    <test-summary>
        <start-time>$self->{'currentdatetime'}</start-time>
        <total-run-time>$self->{'totalruntime'}</total-run-time>
        <test-cases-run>$self->{'totalruncount'}</test-cases-run>
        <test-cases-passed>$self->{'case'}->{'passedcount'}</test-cases-passed>
        <test-cases-failed>$self->{'case'}->{'failedcount'}</test-cases-failed>
        <verifications-passed>$self->{'passedcount'}</verifications-passed>
        <verifications-failed>$self->{'failedcount'}</verifications-failed>
        <average-response-time>$self->{'avgresponse'}</average-response-time>
        <max-response-time>$self->{'maxresponse'}</max-response-time>
        <min-response-time>$self->{'minresponse'}</min-response-time>
    </test-summary>

</results>
|;
    return;
}

################################################################################
# write summary and closing text for STDOUT
sub _writefinalstdout {
    my $self = shift;

    print STDOUT qq|
Start Time: $self->{'currentdatetime'}
Total Run Time: $self->{'totalruntime'} seconds

Test Cases Run: $self->{'totalruncount'}
Test Cases Passed: $self->{'case'}->{'passedcount'}
Test Cases Failed: $self->{'case'}->{'failedcount'}
Verifications Passed: $self->{'passedcount'}
Verifications Failed: $self->{'failedcount'}

|;
    return;
}

################################################################################
sub _http_defaults {
    my $self    = shift;
    my $request = shift;
    
    # add an additional HTTP Header if specified
    if( $self->{'case'}->{addheader} ) {
        # can add multiple headers with a pipe delimiter
        my @addheaders = split( /\|/mx, $self->{'case'}->{addheader} );
        foreach (@addheaders) {
            $_ =~ m~(.*): (.*)~mx;
            $request->header( $1 => $2 );   # using HTTP::Headers Class
        }
        $self->{'case'}->{addheader} = '';
    }

    $self->{'cookie_jar'}->add_cookie_header( $request );

    # print $self->{'request'}->as_string; print "\n\n";

    my $starttimer        = time();
    $self->{'response'}   = $self->{'useragent'}->request( $request );
    my $endtimer          = time();
    my $latency           = ( int( 1000 * ( $endtimer - $starttimer ) ) / 1000 ); # elapsed time rounded to thousandths
    # print $self->{'response'}->as_string; print "\n\n";

    $self->{'cookie_jar'}->extract_cookies( $self->{'response'} );

    #print $self->{'cookie_jar'}->as_string; print "\n\n";
    return($latency,$request);
}

################################################################################
# send http request and read response
sub _httpget {
    my $self = shift;

    my $request = new HTTP::Request( 'GET', $self->{'case'}->{url} );
    return $self->_http_defaults($request);
}

################################################################################
# post request based on specified encoding
sub _httppost {
    my $self = shift;

    if ( $self->{'case'}->{posttype} ) {
        if ( $self->{'case'}->{posttype} =~ m~application/x-www-form-urlencoded~mx ) {
            return $self->_httppost_form_urlencoded();
        }
        elsif ( $self->{'case'}->{posttype} =~ m~multipart/form-data~mx ) {
            return $self->_httppost_form_data();
        }
        elsif (( $self->{'case'}->{posttype} =~ m~text/xml~mx )
            or ( $self->{'case'}->{posttype} =~ m~application/soap+xml~mx ) )
        {
            return $self->_httppost_xml();
        }
        else {
            print STDERR qq|ERROR: Bad Form Encoding Type, I only accept "application/x-www-form-urlencoded", "multipart/form-data", "text/xml", "application/soap+xml" \n|;
        }
    }
    else {
        # use "x-www-form-urlencoded" if no encoding is specified
        $self->{'case'}->{posttype} = 'application/x-www-form-urlencoded';
        return $self->_httppost_form_urlencoded();
    }
    return;
}

################################################################################
# send application/x-www-form-urlencoded HTTP request and read response
sub _httppost_form_urlencoded {
    my $self = shift;

    my $request = new HTTP::Request( 'POST', "$self->{'case'}->{url}" );
    $request->content_type("$self->{'case'}->{posttype}");
    $request->content("$self->{'case'}->{postbody}");

    return $self->_http_defaults($request);
}

################################################################################
# send text/xml HTTP request and read response
sub _httppost_xml {
    my $self       = shift;
    my $resultsxml = $self->{'RESULTSXML'};
    my $results    = $self->{'RESULTS'};

    # read the xml file specified in the testcase
    $self->{'case'}->{postbody} =~ m~file=>(.*)~imx;
    open( my $xmlbody, "<", $self->{'dirname'} . $1 ) or die "\nError: Failed to open text/xml file\n\n";    # open file handle
    my @xmlbody = <$xmlbody>;    # read the file into an array
    close($xmlbody);

    my $request = new HTTP::Request( 'POST', "$self->{'case'}->{url}" );
    $request->content_type("$self->{'case'}->{posttype}");
    $request->content( join( " ", @xmlbody ) );    # load the contents of the file into the request body

    my $latency = $self->_http_defaults($request);

    my $xmlparser = new XML::Parser;
    try {    # see if the XML parses properly
        $xmlparser->parse( $self->{'response'}->content );

        # print "good xml\n";
        unless ( $self->{'config'}->{'reporttype'} ) {      # we suppress most logging when running in a plugin mode
            print $results qq|<span class="pass">Passed XML Parser (content is well-formed)</span><br />\n|;
            print $resultsxml qq|            <verifyxml-success>true</verifyxml-success>\n|;
        }
        unless ( $self->{'nooutput'} ) {        # skip regular STDOUT output
            print STDOUT "Passed XML Parser (content is well-formed) \n";
        }
        $self->{'passedcount'}++;
        return;                                 # exit try block
    }
    catch Error with {
        # get the exception object
        my $ex = shift;
        # print "bad xml\n";
        unless ( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode
            print $results qq|<span class="fail">Failed XML Parser: $ex</span><br />\n|;
            print $resultsxml qq|            <verifyxml-success>false</verifyxml-success>\n|;
        }
        unless ( $self->{'nooutput'} ) {      # skip regular STDOUT output
            print STDOUT "Failed XML Parser: $ex \n";
        }
        $self->{'failedcount'}++;
        $self->{'isfailure'}++;
    };    # <-- remember the semicolon

    return($latency,$request);
}

################################################################################
# send multipart/form-data HTTP request and read response
sub _httppost_form_data {
    my $self = shift;

    my $request = POST "$self->{'case'}->{url}",
      Content_Type => "$self->{'case'}->{posttype}",
      Content      => $self->{'case'}->{postbody};

    return $self->_http_defaults($request);
}

################################################################################
# do verification of http response and print status to HTML/XML/STDOUT/UI
sub _verify {
    my $self       = shift;
    my $resultsxml = $self->{'RESULTSXML'};
    my $results    = $self->{'RESULTS'};

    for (qw/verifypositive verifypositive1 verifypositive2 verifypositive3/) {
        if ( $self->{'case'}->{$_} ) {
            my $regex = $self->{'case'}->{$_};
            $regex =~ s/\ /\\ /gmx;
            # verify existence of string in response
            if( $self->{'response'}->as_string() =~ m~$regex~simx ) {
                unless( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode
                    print $results    qq|<span class="pass">Passed Positive Verification</span><br />\n|;
                    print $resultsxml qq|            <$_-success>true</$_-success>\n|;
                }
                unless( $self->{'nooutput'} ) {    # skip regular STDOUT output
                    print STDOUT "Passed Positive Verification \n";
                }
                $self->{'passedcount'}++;
            }
            else {
                unless( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode
                    print $results    qq|<span class="fail">Failed Positive Verification</span><br />\n|;
                    print $resultsxml qq|            <$_-success>false</$_-success>\n|;
                }
                unless( $self->{'nooutput'} ) {    # skip regular STDOUT output
                    print STDOUT "Failed Positive Verification \n";
                }
                $self->{'failedcount'}++;
                $self->{'isfailure'}++;
            }
        }
    }

    for (qw/verifynegative verifynegative1 verifynegative2 verifynegative3/) {
        if ( $self->{'case'}->{$_} ) {
            my $regex = $self->{'case'}->{$_};
            $regex =~ s/\ /\\ /gmx;
            # verify existence of string in response
            if( $self->{'response'}->as_string() =~ m~$regex~simx ) {
                unless ( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode
                    print $results    qq|<span class="fail">Failed Negative Verification</span><br />\n|;
                    print $resultsxml qq|            <$_-success>false</$_-success>\n|;
                }
                unless ( $self->{'nooutput'} ) {      # skip regular STDOUT output
                    print STDOUT "Failed Negative Verification \n";
                }
                $self->{'failedcount'}++;
                $self->{'isfailure'}++;
            }
            else {
                unless ( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode
                    print $results    qq|<span class="pass">Passed Negative Verification</span><br />\n|;
                    print $resultsxml qq|            <$_-success>true</$_-success>\n|;
                }
                unless ( $self->{'nooutput'} ) {      # skip regular STDOUT output
                    print STDOUT "Passed Negative Verification \n";
                }
                $self->{'passedcount'}++;
            }
        }
    }

    if( $self->{'verifylater'} ) {
        my $regex = $self->{'verifylater'};
        $regex =~ s/\ /\\ /gmx;
        # verify existence of string in response
        if( $self->{'response'}->as_string() =~ m~$regex~simx ) {
            unless( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode
                print $results    qq|<span class="pass">Passed Positive Verification (verification set in previous test case)</span><br />\n|;
                print $resultsxml qq|            <verifypositivenext-success>true</verifypositivenext-success>\n|;
            }
            unless ( $self->{'xnode'} or $self->{'nooutput'} ) { # skip regular STDOUT output if using an XPath or $self->{'nooutput'} is set
                print STDOUT "Passed Positive Verification (verification set in previous test case) \n";
            }
            $self->{'passedcount'}++;
        }
        else {
            unless( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode
                print $results qq|<span class="fail">Failed Positive Verification (verification set in previous test case)</span><br />\n|;
                print $resultsxml qq|            <verifypositivenext-success>false</verifypositivenext-success>\n|;
            }
            unless( $self->{'xnode'} or $self->{'nooutput'} ) { # skip regular STDOUT output if using an XPath or $self->{'nooutput'} is set
                print STDOUT "Failed Positive Verification (verification set in previous test case) \n";
            }
            $self->{'failedcount'}++;
            $self->{'isfailure'}++;
        }
        $self->{'verifylater'} = '';    #set to null after verification
    }

    if( $self->{'verifylaterneg'} ) {
        my $regex = $self->{'verifylaterneg'};
        $regex =~ s/\ /\\ /gmx;
        # verify existence of string in response
        if( $self->{'response'}->as_string() =~ m~$regex~simx ) {
            unless ( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode
                print $results    qq|<span class="fail">Failed Negative Verification (negative verification set in previous test case)</span><br />\n|;
                print $resultsxml qq|            <verifynegativenext-success>false</verifynegativenext-success>\n|;
            }
            unless ( $self->{'xnode'} or $self->{'nooutput'} ) { # skip regular STDOUT output if using an XPath or $self->{'nooutput'} is set
                print STDOUT "Failed Negative Verification (negative verification set in previous test case) \n";
            }
            $self->{'failedcount'}++;
            $self->{'isfailure'}++;
        }
        else {
            unless ( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode
                print $results qq|<span class="pass">Passed Negative Verification (negative verification set in previous test case)</span><br />\n|;
                print $resultsxml qq|            <verifynegativenext-success>true</verifynegativenext-success>\n|;
            }
            unless ( $self->{'xnode'} or $self->{'nooutput'} ) { # skip regular STDOUT output if using an XPath or $self->{'nooutput'} is set
                print STDOUT "Passed Negative Verification (negative verification set in previous test case) \n";
            }
            $self->{'passedcount'}++;
        }
        $self->{'verifylaterneg'} = '';    # set to null after verification
    }

    if( $self->{'case'}->{verifyresponsecode} ) {
        # verify returned HTTP response code matches verifyresponsecode set in test case
        if ( $self->{'case'}->{verifyresponsecode} == $self->{'response'}->code() )
        {
            unless ( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode
                print $results qq|<span class="pass">Passed HTTP Response Code Verification </span><br />\n|;
                print $resultsxml qq|            <verifyresponsecode-success>true</verifyresponsecode-success>\n|;
                print $resultsxml qq|            <verifyresponsecode-message>Passed HTTP Response Code Verification</verifyresponsecode-message>\n|;
            }
            unless ( $self->{'nooutput'} ) {    # skip regular STDOUT output
                print STDOUT qq|Passed HTTP Response Code Verification \n|;
            }
            $self->{'passedcount'}++;
        }
        else {
            unless ( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode
                print $results qq|<span class="fail">Failed HTTP Response Code Verification (received |. $self->{'response'}->code().qq|, expecting $self->{'case'}->{verifyresponsecode})</span><br />\n|;
                print $resultsxml qq|            <verifyresponsecode-success>false</verifyresponsecode-success>\n|;
                print $resultsxml qq|            <verifyresponsecode-message>Failed HTTP Response Code Verification (received |.$self->{'response'}->code().qq|, expecting $self->{'case'}->{verifyresponsecode})</verifyresponsecode-message>\n|;
            }
            unless ( $self->{'nooutput'} ) {    #skip regular STDOUT output
                print STDOUT qq|Failed HTTP Response Code Verification (received |.$self->{'response'}->code().qq|, expecting $self->{'case'}->{verifyresponsecode}) \n|;
            }
            $self->{'failedcount'}++;
            $self->{'isfailure'}++;
        }
    }
    else {
        # verify http response code is in the 100-399 range
        if( $self->{'response'}->as_string() =~ /HTTP\/1.(0|1)\ (1|2|3)/imx ) {     # verify existance of string in response
            unless( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode
                print $results qq|<span class="pass">Passed HTTP Response Code Verification (not in error range)</span><br />\n|;
                print $resultsxml qq|            <verifyresponsecode-success>true</verifyresponsecode-success>\n|;
                print $resultsxml qq|            <verifyresponsecode-message>Passed HTTP Response Code Verification (not in error range)</verifyresponsecode-message>\n|;
            }
            unless( $self->{'nooutput'} ) {    #skip regular STDOUT output
                print STDOUT qq|Passed HTTP Response Code Verification (not in error range) \n|;
            }

            # succesful response codes: 100-399
            $self->{'passedcount'}++;
        }
        else {
            $self->{'response'}->as_string() =~ /(HTTP\/1.)(.*)/mxi;
            if ($1) {    #this is true if an HTTP response returned
                unless( $self->{'config'}->{'reporttype'} )
                {        #we suppress most logging when running in a plugin mode
                    print $results qq|<span class="fail">Failed HTTP Response Code Verification ($1$2)</span><br />\n|;    #($1$2) is HTTP response code
                    print $resultsxml qq|            <verifyresponsecode-success>false</verifyresponsecode-success>\n|;
                    print $resultsxml qq|            <verifyresponsecode-message>Failed HTTP Response Code Verification ($1$2)</verifyresponsecode-message>\n|;
                }
                unless ( $self->{'nooutput'} ) {    #skip regular STDOUT output
                    print STDOUT "Failed HTTP Response Code Verification ($1$2) \n";    #($1$2) is HTTP response code
                }
            }
            else
            { #no HTTP response returned.. could be error in connection, bad hostname/address, or can not connect to web server
                unless( $self->{'config'}->{'reporttype'} ) {    #we suppress most logging when running in a plugin mode
                    print $results qq|<span class="fail">Failed - No Response</span><br />\n|;    #($1$2) is HTTP response code
                    print $resultsxml qq|            <verifyresponsecode-success>false</verifyresponsecode-success>\n|;
                    print $resultsxml qq|            <verifyresponsecode-message>Failed - No Response</verifyresponsecode-message>\n|;
                }
                unless( $self->{'nooutput'} ) {    #skip regular STDOUT output
                    print STDOUT "Failed - No Response \n";   #($1$2) is HTTP response code
                }
            }
            $self->{'failedcount'}++;
            $self->{'isfailure'}++;
        }
    }
    return;
}

################################################################################
# parse values from responses for use in future request (for session id's, dynamic URL rewriting, etc)
sub _parseresponse {
    my $self = shift;

    my ( $resptoparse, @parseargs );
    my ( $leftboundary, $rightboundary, $escape );

    for( qw/parseresponse parseresponse1 parseresponse2 parseresponse3 parseresponse4 parseresponse5/ ) {

        next unless $self->{'case'}->{$_};

        @parseargs = split( /\|/mx, $self->{'case'}->{$_} );

        $leftboundary  = $parseargs[0];
        $rightboundary = $parseargs[1];
        $escape        = $parseargs[2];

        $resptoparse = $self->{'response'}->as_string;
        if ( $resptoparse =~ m~$leftboundary(.*?)$rightboundary~smx ) {
            $self->{'parsedresult'}->{$_} = $1;
        }

        if ($escape) {
            if ( $escape eq 'escape' ) {
                $self->{'parsedresult'}->{$_} =
                  $self->_url_escape( $self->{'parsedresult'}->{$_} );
            }
        }

        #print "\n\nParsed String: $self->{'parsedresult'}->{$_}\n\n";
    }
    return;
}

################################################################################
# get test case files to run (from command line or config file) and evaluate constants
sub _processcasefile {
    # parse config file and grab values it sets
    my $self = shift;

    my @configfile;
    my $comment_mode;
    my $firstparse;
    my $filename;
    my $xpath;
    my $setuseragent;
    my $config;

    undef $self->{'casefilelist'};    # empty the array of test case filenames
    undef @configfile;

    # process the config file
    # if -c option was set on command line, use specified config file
    if($self->{'opt_configfile'} ) {
        open( $config, '<', $self->{'dirname'} . $self->{'opt_configfile'} )
          or die "\nERROR: Failed to open ". $self->{'opt_configfile'}. " file: $!\n\n";
        $self->{'config'}->{'exists'} = 1;   # flag we are going to use a config file
    }
    # if config.xml exists, read it
    elsif( -e $self->{'dirname'}."config.xml" ) {
        open( $config, '<', $self->{'dirname'} . "config.xml" )
          or die "\nERROR: Failed to open config.xml file: $!\n\n";
        $self->{'config'}->{'exists'} = 1; # flag we are going to use a config file
    }

    if( $self->{'config'}->{'exists'} ) {    #if we have a config file, use it

        my @precomment = <$config>;    #read the config file into an array

        #remove any commented blocks from config file
        foreach (@precomment) {
            unless (m~<comment>.*</comment>~mx) {    # single line comment
                                                     # multi-line comments
                if (/<comment>/mx) {
                    $comment_mode = 1;
                }
                elsif (m~</comment>~mx) {
                    $comment_mode = 0;
                }
                elsif ( !$comment_mode ) {
                    push( @configfile, $_ );
                }
            }
        }
        close($config);
    }

    if( ( $#ARGV + 1 ) < 1 ) {    #no command line args were passed
        # if testcase filename is not passed on the command line, use files in config.xml
        # parse test case file names from config.xml and build array
        foreach (@configfile) {

            if (/<testcasefile>/mx) {
                $firstparse = $';    #print "$' \n\n";
                $firstparse =~ m~</testcasefile>~mx;
                $filename = $`;      #string between tags will be in $filename
                #print "\n$filename \n\n";
                push @{ $self->{'casefilelist'} }, $filename;         #add next filename we grab to end of array
            }
        }

        unless( $self->{'casefilelist'}->[0] ) {
            if ( -e "$self->{'dirname'}" . "testcases.xml" ) {

                # not appending a $self->{'dirname'} here since we append one when we open the file
                push @{ $self->{'casefilelist'} }, "testcases.xml"; #if no files are specified in config.xml, default to testcases.xml
            }
            else {
                die "\nERROR: I can't find any test case files to run.\nYou must either use a config file or pass a filename "
                  . "on the command line if you are not using the default testcase file (testcases.xml).";
            }
        }
    }

    elsif( ( $#ARGV + 1 ) == 1 ) {    # one command line arg was passed
        # use testcase filename passed on command line (config.xml is only used for other options)
        push @{ $self->{'casefilelist'} }, $ARGV[0]; # first commandline argument is the test case file, put this on the array for processing
    }

    elsif( ( $#ARGV + 1 ) == 2 ) {     # two command line args were passed

        undef $self->{'xnode'};        # reset xnode
        undef $xpath;                  # reset xpath

        $xpath = $ARGV[1];

        if ( $xpath =~ /\/(.*)\[/mx ) {    # if the argument contains a "/" and "[", it is really an XPath
            $xpath =~ /(.*)\/(.*)\[(.*?)\]/mx;    #if it contains XPath info, just grab the file name
            $self->{'xnode'} = $3;    # grab the XPath Node value.. (from inside the "[]")
            # print "\nXPath Node is: $self->{'xnode'} \n";
        }
        else {
            print STDERR "\nSorry, $xpath is not in the XPath format I was expecting, I'm ignoring it...\n";
        }

        # use testcase filename passed on command line (config.xml is only used for other options)
        push @{ $self->{'casefilelist'} }, $ARGV[0]; # first command line argument is the test case file, put this on the array for processing
    }

    elsif ( ( $#ARGV + 1 ) > 2 ) {    #too many command line args were passed
        die "\nERROR: Too many arguments\n\n";
    }

    #print "\ntestcase file list: @{$self->{'casefilelist'}}\n\n";

    #grab values for constants in config file:
    foreach (@configfile) {

        for my $config (
            qw/baseurl baseurl1 baseurl2 gnuplot proxy timeout
            globaltimeout globalhttplog standaloneplot/
          )
        {

            if (/<$config>/mx) {
                $_ =~ m~<$config>(.*)</$config>~mx;
                $self->{'config'}->{$config} = $1;

                #print "\n$_ : $self->{'config'}->{$_} \n\n";
            }
        }

        if (/<reporttype>/mx) {
            $_ =~ m~<reporttype>(.*)</reporttype>~mx;
            if ( $1 ne "standard" ) {
                $self->{'config'}->{'reporttype'} = $1;
                $self->{'nooutput'}   = "set";
            }

            #print "\nreporttype : $self->{'config'}->{'reporttype'} \n\n";
        }

        if (/<useragent>/mx) {
            $_ =~ m~<useragent>(.*)</useragent>~mx;
            $setuseragent = $1;
            if ($setuseragent)
            {    #http useragent that will show up in webserver logs
                $self->{'useragent'}->agent($setuseragent);
            }

            #print "\nuseragent : $setuseragent \n\n";
        }

        if (/<httpauth>/mx) {

            #each time we see an <httpauth>, we set @authentry to be the
            #array of values, then we use [] to get a reference to that array
            #and push that reference onto @httpauth.
            my @authentry;
            $_ =~ m~<httpauth>(.*)</httpauth>~mx;
            @authentry = split( /:/mx, $1 );
            if ( $#authentry != 4 ) {
                print STDERR "\nError: httpauth should have 5 fields delimited by colons\n\n";
            }
            else {
                push( @{ $self->{'config'}->{'httpauth'} }, [@authentry] );
            }

            #print "\nhttpauth : @{$self->{'config'}->{'httpauth'}} \n\n";
        }
    }

    return;
}

################################################################################
# here we do some pre-processing of the test case file and write it out to a temp file.
# we convert certain chars so xml parser doesn't puke.
sub _convtestcases {
    my $self            = shift;
    my $currentcasefile = shift;

    my @xmltoconvert;

    my ( $fh, $tempfilename ) = tempfile();
    my $filename = $self->{'dirname'} . $currentcasefile;
    open( my $xmltoconvert, '<', $filename )
      or die "\nError: Failed to open test case file: "
      . $filename
      . ": $!\n\n";    #open file handle
    @xmltoconvert = <$xmltoconvert>;    #read the file into an array

    $self->{'casecount'} = 0;

    foreach (@xmltoconvert) {

        # convert escaped chars and certain reserved chars to temporary values that the parser can handle
        # these are converted back later in processing
        s/&/{AMPERSAND}/gmx;
        s/\\</{LESSTHAN}/gmx;

        # count cases while we are here
        if ( $_ =~ /<case/mx ) {        #count test cases based on '<case' tag
            $self->{'casecount'}++;
        }
    }

    close($xmltoconvert);

    # open file handle to temp file
    open( $xmltoconvert, '>', $tempfilename )
      or die "\nERROR: Failed to open temp file for writing: $!\n\n";
    print $xmltoconvert @xmltoconvert;  # overwrite file with converted array
    close($xmltoconvert);
    return $tempfilename;
}

################################################################################
# converts replaced xml with substitutions
sub _convertbackxml {
    my ( $self, $string, $timestamp ) = @_;
    return unless defined $string;
    $string =~ s~{AMPERSAND}~&~gmx;
    $string =~ s~{LESSTHAN}~<~gmx;
    $string =~ s~{TIMESTAMP}~$timestamp~gmx;
    $string =~ s~{BASEURL}~$self->{'config'}->{baseurl}~gmx;
    $string =~ s~{BASEURL1}~$self->{'config'}->{baseurl1}~gmx;
    $string =~ s~{BASEURL2}~$self->{'config'}->{baseurl2}~gmx;
    $string =~ s~{PARSEDRESULT}~$self->{'parsedresult'}->{parseresponse}~gmx;
    $string =~ s~{PARSEDRESULT1}~$self->{'parsedresult'}->{parseresponse1}~gmx;
    $string =~ s~{PARSEDRESULT2}~$self->{'parsedresult'}->{parseresponse2}~gmx;
    $string =~ s~{PARSEDRESULT3}~$self->{'parsedresult'}->{parseresponse3}~gmx;
    $string =~ s~{PARSEDRESULT4}~$self->{'parsedresult'}->{parseresponse4}~gmx;
    $string =~ s~{PARSEDRESULT5}~$self->{'parsedresult'}->{parseresponse5}~gmx;
    return $string;
}

################################################################################
# escapes difficult characters with %hexvalue
sub _url_escape {
    my ( $self, @values ) = @_;

    # LWP handles url encoding already, but use this to escape valid chars that LWP won't convert (like +)
    my @return;
    for my $val (@values) {
        $val =~ s/[^-\w.,!~'()\/\ ]/uc sprintf "%%%02x", ord $&/egmx;
        push @return, $val;
    }
    return wantarray ? @return : $return[0];
}

################################################################################
# write requests and responses to http.log file
sub _httplog {
    my $self        = shift;
    my $request     = shift;
    my $httplogfile = $self->{'HTTPLOGFILE'};

    unless( $self->{'config'}->{'reporttype'} ) {    # we suppress most logging when running in a plugin mode

        if ( $self->{'case'}->{logrequest}
            && ( $self->{'case'}->{logrequest} =~ /yes/mxi ) )
        {    # http request - log setting per test case
            print $httplogfile $request->as_string, "\n\n";
        }

        if ( $self->{'case'}->{logresponse}
            && ( $self->{'case'}->{logresponse} =~ /yes/mxi ) )
        {    # http response - log setting per test case
            print $httplogfile $self->{'response'}->as_string, "\n\n";
        }

        if ( $self->{'config'}->{globalhttplog}
            && ( $self->{'config'}->{globalhttplog} =~ /yes/mxi ) )
        {    # global http log setting
            print $httplogfile $request->as_string,  "\n\n";
            print $httplogfile $self->{'response'}->as_string, "\n\n";
        }

        if (
            (
                $self->{'config'}->{globalhttplog}
                && ( $self->{'config'}->{globalhttplog} =~ /onfail/mxi )
            )
            && ( $self->{'isfailure'} > 0 )
          )
        {    # global http log setting - onfail mode
            print $httplogfile $request->as_string,  "\n\n";
            print $httplogfile $self->{'response'}->as_string, "\n\n";
        }

        if (
            (
                $self->{'case'}->{logrequest}
                && ( $self->{'case'}->{logrequest} =~ /yes/mxi )
            )
            or ( $self->{'case'}->{logresponse}
                && ( $self->{'case'}->{logresponse} =~ /yes/mxi ) )
            or ( $self->{'config'}->{globalhttplog}
                && ( $self->{'config'}->{globalhttplog} =~ /yes/mxi ) )
            or (
                (
                    $self->{'config'}->{globalhttplog}
                    && ( $self->{'config'}->{globalhttplog} =~ /onfail/mxi )
                )
                && ( $self->{'isfailure'} > 0 )
            )
          )
        {
            print $httplogfile "\n************************* LOG SEPARATOR *************************\n\n\n";
        }
    }
    return;
}

################################################################################
# write performance results to plot.log in the format gnuplot can use
sub _plotlog {
    my ( $self, $value ) = @_;

    my ( %months, $date, $time, $mon, $mday, $hours, $min, $sec, $year );

    # do this unless: monitor is disabled in gui, or running standalone mode without config setting to turn on plotting
    unless(
        (
                ( $self->{'gui'} )
            and ( $self->{'monitorenabledchkbx'} eq 'monitor_off' )
        )
        or (    ( !defined $self->{'gui'} )
            and ( $self->{'config'}->{standaloneplot} ne 'on' ) )
      )
    {

        %months = (
            "Jan" => 1,
            "Feb" => 2,
            "Mar" => 3,
            "Apr" => 4,
            "May" => 5,
            "Jun" => 6,
            "Jul" => 7,
            "Aug" => 8,
            "Sep" => 9,
            "Oct" => 10,
            "Nov" => 11,
            "Dec" => 12
        );

        $date = scalar localtime;
        ($mon, $mday, $hours, $min, $sec, $year) = $date =~ /\w+\ (\w+)\ +(\d+)\ (\d\d):(\d\d):(\d\d)\ (\d\d\d\d)/mx;
        $time = "$months{$mon} $mday $hours $min $sec $year";

        my $plotlog;
        if ( $self->{'plotclear'} eq 'yes' )
        {    #used to clear the graph when requested
            open( $plotlog, '>', $self->{'dirname'} . "plot.log" )
              or die "ERROR: Failed to open file plot.log: $!\n"
              ;    #open in clobber mode so log gets truncated
            $self->{'plotclear'} = 'no';    #reset the value
        }
        else {
            open( $plotlog, '>>', $self->{'dirname'} . "plot.log" )
              or die
              "ERROR: Failed to open file plot.log: $!\n";  #open in append mode
        }

        printf $plotlog "%s %2.4f\n", $time, $value;
        close($plotlog);
    }
    return;
}

################################################################################
# create gnuplot config file
sub _gnuplotcfg {
    my $self = shift;

    # do this unless: monitor is disabled in gui, or running standalone mode without config setting to turn on plotting
    unless (
        (
                ( $self->{'gui'} )
            and ( $self->{'monitorenabledchkbx'} eq 'monitor_off' )
        )
        or (    ( !defined $self->{'gui'} )
            and ( $self->{'config'}->{standaloneplot} ne 'on' ) )
      )
    {

        open( my $gnuplotplt, ">$self->{'dirname'}" . "plot.plt" )
          || die "Could not open file\n";
        print $gnuplotplt qq|
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
plot \"plot.log\" using 1:7 title \"Response Times" w $self->{'config'}->{'graphtype'}
|;
        close($gnuplotplt);

    }
    return;
}

################################################################################
# do ending tasks
sub _finaltasks {
    my $self = shift;

    if ( $self->{'gui'} ) { $self->_gui_stop(); }

    unless( $self->{'config'}->{'reporttype'} )
    {    #we suppress most logging when running in a plugin mode
        $self->_writefinalhtml();    #write summary and closing tags for results file
    }

    unless( $self->{'xnode'} or $self->{'config'}->{'reporttype'} )
    { #skip regular STDOUT output if using an XPath or $self->{'config'}->{'reporttype'} is set ("standard" does not set this)
        $self->_writefinalstdout();   #write summary and closing tags for STDOUT
    }

    unless( $self->{'config'}->{'reporttype'} )
    {    #we suppress most logging when running in a plugin mode
        $self->_writefinalxml();    #write summary and closing tags for XML results file
    }

    unless( $self->{'config'}->{'reporttype'} )
    {          #we suppress most logging when running in a plugin mode
               #these handles shouldn't be open
        close( $self->{'HTTPLOGFILE'} );
        close( $self->{'RESULTS'} );
        close( $self->{'RESULTSXML'} );
    }

    #plugin modes
    if ( $self->{'config'}->{'reporttype'} )
    {          #return value is set which corresponds to a monitoring program

        #Nagios plugin compatibility
        if ( $self->{'config'}->{'reporttype'} eq 'nagios' )
        {      #report results in Nagios format
            my $end =
              defined $self->{'config'}->{globaltimeout}
              ? "$self->{'config'}->{globaltimeout};;0"
              : ";;0";

            if ( $self->{'case'}->{'failedcount'} > 0 ) {
                print "WebInject CRITICAL - $self->{'returnmessage'} |time=$self->{'totalruntime'};$end\n";
                exit $self->{'exit_codes'}->{'CRITICAL'};
            }
            elsif (
                ( $self->{'config'}->{globaltimeout} )
                && ( $self->{'totalruntime'} >
                    $self->{'config'}->{globaltimeout} )
              )
            {
                print "WebInject WARNING - All tests passed successfully but global timeout ($self->{'config'}->{globaltimeout} seconds) has been reached |time=$self->{'totalruntime'};$end\n";
                exit $self->{'exit_codes'}->{'WARNING'};
            }
            else {
                print "WebInject OK - All tests passed successfully in $self->{'totalruntime'} seconds |time=$self->{'totalruntime'};$end\n";
                exit $self->{'exit_codes'}->{'OK'};
            }
        }

        #MRTG plugin compatibility
        elsif ( $self->{'config'}->{'reporttype'} eq 'mrtg' )
        {    #report results in MRTG format
            if ( $self->{'case'}->{'failedcount'} > 0 ) {
                print "$self->{'totalruntime'}\n$self->{'totalruntime'}\n\nWebInject CRITICAL - $self->{'returnmessage'} \n";
                exit(0);
            }
            else {
                print "$self->{'totalruntime'}\n$self->{'totalruntime'}\n\nWebInject OK - All tests passed successfully in $self->{'totalruntime'} seconds \n";
                exit(0);
            }
        }

        #External plugin. To use it, add something like that in the config file:
        # <reporttype>external:/home/webinject/Plugin.pm</reporttype>
        elsif ( $self->{'config'}->{'reporttype'} =~ /^external:(.*)/mx ) {
            unless ( my $return = do $1 ) {
                die "couldn't parse $1: $@\n" if $@;
                die "couldn't do $1: $!\n" unless defined $return;
                die "couldn't run $1\n" unless $return;
            }
        }

        else {
            print STDERR "\nError: only 'nagios', 'mrtg', 'external', or 'standard' are supported reporttype values\n\n";
        }

    }
    return;
}

################################################################################
# delete any files leftover from previous run if they exist
sub _whackoldfiles {
    my $self = shift;

    if ( -e $self->{'dirname'} . "plot.log" ) {
        unlink $self->{'dirname'} . "plot.log";
    }
    if ( -e $self->{'dirname'} . "plot.plt" ) {
        unlink $self->{'dirname'} . "plot.plt";
    }
    if ( -e $self->{'dirname'} . "plot.png" ) {
        unlink $self->{'dirname'} . "plot.png";
    }
    if ( glob( $self->{'dirname'} . "*.xml.tmp" ) ) {
        unlink glob( $self->{'dirname'} . "*.xml.tmp" );
    }

    # verify files are deleted, if not give the filesystem time to delete them before continuing
    while (( -e "plot.log" )
        or ( -e "plot.plt" )
        or ( -e "plot.png" )
        or ( glob('*.xml.tmp') ) )
    {
        sleep .5;
    }
    return;
}

################################################################################
# call the external plotter to create a graph (if we are in the appropriate mode)
sub _plotit {
    my $self = shift;

    # do this unless: monitor is disabled in gui, or running standalone mode without config setting to turn on plotting
    unless (
        (
                ( $self->{'gui'} )
            and ( $self->{'monitorenabledchkbx'} eq 'monitor_off' )
        )
        or (    ( !defined $self->{'gui'} )
            and ( $self->{'config'}->{standaloneplot} ne 'on' ) )
      )
    {
        # do this unless its being called from the gui with No Graph set
        unless ( $self->{'config'}->{'graphtype'} eq 'nograph' )
        {
            my $gnuplot;
            if(defined $self->{'config'}->{gnuplot}) {
                $gnuplot = $self->{'config'}->{gnuplot}
            }
            elsif($^O eq 'MSWin32') {
                $gnuplot = "./wgnupl32.exe";
            } else {
                $gnuplot = "/usr/bin/gnuplot";
            }

            # if gnuplot exists
            if( -e $gnuplot ) {
                system $gnuplot, "plot.plt";    # plot it
            }
            elsif( $self->{'gui'} ) {
                # if gnuplot not specified, notify on gui
                $self->_gui_no_plotter_found();
            }
        }
    }
    return;
}

################################################################################
# get the directory webinject engine is running from
sub _getdirname {
    my $self = shift;

    $self->{'dirname'} = "";

    #$self->{'dirname'} = $0;
    #$self->{'dirname'} =~ s~(.*/).*~$1~;  #for nix systems
    #$self->{'dirname'} =~ s~(.*\\).*~$1~; #for windoz systems
    #if ($self->{'dirname'} eq $0) {
    #    $self->{'dirname'} = './';
    #}
    return;
}

################################################################################
# command line options
sub _getoptions {
    my $self = shift;

    my ( @sets, $opt_version );
    Getopt::Long::Configure('bundling');
    unless(
        GetOptions(
            'v|V|version' => \$opt_version,
            'c|config=s'  => \$self->{'opt_configfile'},
            'o|output=s'  => \$self->{'opt_output'},
            'n|no-output' => \$self->{'nooutput'},
            's=s'         => \@sets,
        )
      )
    {
        print <<EOB;
    Usage:
      webinject.pl [-c|--config config_file] [-o|--output output_location] [-n|--no-output] [-s key=value] [testcase_file [XPath]]
      webinject.pl --version|-v
EOB
        exit(1);
    }
    if ($opt_version) {
        print
"WebInject version $Webinject::VERSION\nFor more info: http://www.webinject.org\n";
        exit();
    }
    for my $set (@sets) {
        my ( $key, $val ) = split /=/mx, $set, 2;
        $self->{'config'}->{ lc $key } = $val;
    }
    return;
}

=head1 SEE ALSO

For more information about webinject visit http://www.webinject.org

=head1 AUTHOR

Corey Goldberg, E<lt>corey@goldb.orgE<gt>
Sven Nierlein, E<lt>nierlein@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Sven Nierlein
Copyright (C) 2004-2006 by Corey Goldberg

This library is free software; you can redistribute it under the GPL2 license.

=cut

1;
__END__
