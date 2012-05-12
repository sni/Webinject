package Webinject;

#    Copyright 2010-2012 Sven Nierlein (nierlein@cpan.org)
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

our $VERSION = '1.74';

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

=over 4

=item reporttype

possible values are 'standard', 'nagios', 'nagios2', 'mrtg' or 'external:'

=item nooutput

suppress all output to STDOUT, create only logilfes

=item break_on_errors

stop after the first testcase fails, otherwise Webinject would go on and
execute all tests regardless of the previous case.

=item timeout

Default timeout is 180seconds. Timeout starts again for every testcase.

=item useragent

Set the useragent used in HTTP requests. Default is 'Webinject'.

=item max_redirect

Set maximum number of HTTP redirects. Default is 0.

=item proxy

Sets a proxy which is then used for http and https requests.

=item output_dir

Output directory where all logfiles will go to. Defaults to current directory.

=item globalhttplog

Can be 'yes' or 'onfail'. Will log the http request and response to a http.log file.

=item httpauth

Provides credentials for webserver authentications. The format is:

  ['servername', 'portnumber', 'realm-name', 'username', 'password']

=item baseurl

the value can be used as {BASEURL} in the test cases

=item baseurl1

the value can be used as {BASEURL1} in the test cases

=item baseurl2

the value can be used as {BASEURL2} in the test cases

=item standaloneplot

can be "on" or "off". Default is off.
Create gnuplot graphs when enabled.

=item graphtype

Defaults to 'lines'

=item gnuplot

Defines the path to your gnuplot binary.

=back

=cut

sub new {
    my $class     = shift;
    my (%options) = @_;
    $|            = 1;     # don't buffer output to STDOUT

    my $self = {};
    bless $self, $class;

    # set default config options
    $self->_set_defaults();

    for my $opt_key ( keys %options ) {
        if( exists $self->{'config'}->{$opt_key} ) {
            if($opt_key eq 'httpauth') {
                $self->_set_http_auth($options{$opt_key});
            } else {
                $self->{'config'}->{$opt_key} = $options{$opt_key};
            }
        }
        else {
            $self->_usage("ERROR: unknown option: ".$opt_key);
        }
    }

    # get command line options
    $self->_getoptions();

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

    if($self->{'gui'}) {
        $self->_gui_initial();
    }
    else {
        # delete files leftover from previous run (do this here so they are whacked each run)
        $self->_whackoldfiles();
    }

    $self->_processcasefile();

    my $useragent = $self->_get_useragent();

    # write opening tags for STDOUT.
    $self->_writeinitialstdout();

    # create the gnuplot config file
    $self->_plotcfg();

    # timer for entire test run
    my $startruntimer = time();

    # process test case files named in config
    for my $currentcasefile ( @{ $self->{'casefilelist'} } ) {
        #print "\n$currentcasefile\n\n";

        my $resultfile = {
            'name'  => $currentcasefile,
            'cases' => [],
        };

        if($self->{'gui'}) { $self->_gui_processing_msg($currentcasefile); }

        my $tempfile = $self->_convtestcases($currentcasefile);

        my $xmltestcases;
        eval {
            $xmltestcases = XMLin( $tempfile,
                                  varattr   => 'varname',
                                  variables => $self->{'config'} );    # slurp test case file to parse (and specify variables tag)
        };
        if($@) {
            my $error = $@;
            $error =~ s/^\s*//mx;
            $self->_usage("ERROR: reading xml test case ".$currentcasefile." failed: ".$error);
        }

        unless( defined $xmltestcases->{case} ) {
            $self->_usage("ERROR: no test cases defined!");
        }

        # fix case if there is only one case
        if( defined $xmltestcases->{'case'}->{'id'} ) {
            my $tmpcase = $xmltestcases->{'case'};
            $xmltestcases->{'case'} = { $tmpcase->{'id'} => $tmpcase };
        }

        #delete the temp file as soon as we are done reading it
        if ( -e $tempfile ) { unlink $tempfile; }

        my $repeat = 1;
        if(defined $xmltestcases->{repeat} and $xmltestcases->{repeat} > 0) {
            $repeat = $xmltestcases->{repeat};
        }

        my $useragent = $self->_get_useragent();

        for my $run_nr (1 .. $repeat) {

            # process cases in sorted order
            for my $testnum ( sort { $a <=> $b } keys %{ $xmltestcases->{case} } ) {

                # if an XPath Node is defined, only process the single Node
                if( $self->{'xnode'} ) {
                    $testnum = $self->{'xnode'};
                }

                # create testcase
                my $case = { 'id' => $testnum };

                # populate variables with values from testcase file, do substitutions, and revert converted values back
                for my $key (keys %{$xmltestcases->{'case'}->{$testnum}}) {
                    $case->{$key} = $xmltestcases->{'case'}->{$testnum}->{$key};
                }

                my $label = '';
                if(defined $case->{'label'}) {
                    $label = $case->{'label'}." - ";
                }
                $self->_out(qq|Test: $label$currentcasefile - $testnum \n|);

                $case = $self->_run_test_case($case, $useragent);

                push @{$resultfile->{'cases'}}, $case;

                # break from sub if user presses stop button in gui
                if( $self->{'switches'}->{'stop'} eq 'yes' ) {
                    my $rc = $self->_finaltasks();
                    $self->{'switches'}->{'stop'} = 'no';
                    return $rc;    # break from sub
                }

                # break here if the last result was an error
                if($self->{'config'}->{'break_on_errors'} and $self->{'result'}->{'iscritical'}) {
                    last;
                }

                # if an XPath Node is defined, only process the single Node
                if( $self->{'xnode'} ) {
                    last;
                }
            }
        }

        push @{$self->{'result'}->{'files'}}, $resultfile;
    }

    my $endruntimer = time();
    $self->{'result'}->{'totalruntime'} = ( int( 1000 * ( $endruntimer - $startruntimer ) ) / 1000 );    #elapsed time rounded to thousandths


    # do return/cleanup tasks
    return $self->_finaltasks();
}

################################################################################
# runs a single test case
sub _run_test_case {
    my($self,$case,$useragent) =@_;

    confess("no testcase!") unless defined $case;

    $case->{'id'}          = 1 unless defined $case->{'id'};
    $case->{'passedcount'} = 0;
    $case->{'failedcount'} = 0;
    $case->{'iswarning'}   = 0;
    $case->{'iscritical'}  = 0;
    $case->{'messages'}    = [];

    $useragent = $self->_get_useragent() unless defined $useragent;

    # don't do this if monitor is disabled in gui
    if($self->{'gui'} and $self->{'monitorenabledchkbx'} ne 'monitor_off') {
        my $curgraphtype = $self->{'config'}->{'graphtype'};
    }

    # used to replace parsed {timestamp} with real timestamp value
    my $timestamp = time();

    for my $key (keys %{$case}) {
        $case->{$key} = $self->_convertbackxml($case->{$key}, $timestamp);
        next if $key eq 'errormessage';
        $case->{$key} = $self->_convertbackxmlresult($case->{$key}, $timestamp);
    }

    if( $self->{'gui'} ) { $self->_gui_tc_descript($case); }

    push @{$case->{'messages'}}, { 'html' => "<td>" }; # HTML: open table column
    for(qw/description1 description2/) {
        next unless defined $case->{$_};
        $self->_out(qq|Desc: $case->{$_}\n|);
        push @{$case->{'messages'}}, {'key' => $_, 'value' => $case->{$_}, 'html' => "<b>$case->{$_}</b><br />" };
    }
    my $method;
    if (defined $case->{method}) {
        $method = uc($case->{method});
    } else {
        $method = "GET";
    }
    push @{$case->{'messages'}}, { 'html' => qq|<small>$method <a href="$case->{url}">$case->{url}</a> </small><br />\n| };

    push @{$case->{'messages'}}, { 'html' => "</td><td>" }; # HTML: next column

    my($latency,$request,$response);
    if($case->{method}){
        if(lc $case->{method} eq "get") {
            ($latency,$request,$response) = $self->_httpget($useragent, $case);
        }
        elsif(lc $case->{method} eq "post") {
            ($latency,$request,$response) = $self->_httppost($useragent, $case);
        }
        else {
            $self->_usage('ERROR: bad HTTP Request Method Type, you must use "get" or "post"');
        }
    }
    else {
        ($latency,$request,$response) = $self->_httpget($useragent, $case);     # use "get" if no method is specified
    }
    $case->{'latency'}  = $latency;
    $case->{'request'}  = $request->as_string();
    $case->{'response'} = $response->as_string();

    # verify result from http response
    $self->_verify($response, $case);

    if($case->{verifypositivenext}) {
        $self->{'verifylater'} = $case->{'verifypositivenext'};
        $self->_out("Verify On Next Case: '".$case->{verifypositivenext}."' \n");
        push @{$case->{'messages'}}, {'key' => 'verifypositivenext', 'value' => $case->{verifypositivenext}, 'html' => "Verify On Next Case: ".$case->{verifypositivenext}."<br />" };
    }

    if($case->{verifynegativenext}) {
        $self->{'verifylaterneg'} = $case->{'verifynegativenext'};
        $self->_out("Verify Negative On Next Case: '".$case->{verifynegativenext}."' \n");
        push @{$case->{'messages'}}, {'key' => 'verifynegativenext', 'value' => $case->{verifynegativenext}, 'html' => "Verify Negative On Next Case: ".$case->{verifynegativenext}."<br />" };
    }

    # write to http.log file
    $self->_httplog($request, $response, $case);

    # send perf data to log file for plotting
    $self->_plotlog($latency);

    # call the external plotter to create a graph
    $self->_plotit();

    if( $self->{'gui'} ) {
        $self->_gui_updatemontab();                 # update monitor with the newly rendered plot graph
    }

    $self->_parseresponse($response, $case);        # grab string from response to send later

    # make parsed results available in the errormessage
    for my $key (keys %{$case}) {
        next unless $key eq 'errormessage';
        $case->{$key} = $self->_convertbackxmlresult($case->{$key}, $timestamp);
    }

    push @{$case->{'messages'}}, { 'html' => "</td><td>\n" }; # HTML: next column
    # if any verification fails, test case is considered a failure
    if($case->{'iscritical'}) {
        # end result will be also critical
        $self->{'result'}->{'iscritical'} = 1;

        push @{$case->{'messages'}}, {'key' => 'success', 'value' => 'false' };
        if( $self->{'result'}->{'returnmessage'} ) {       # Add returnmessage to the output
            my $prefix = "case #".$case->{'id'}.": ";
            if(defined $case->{'label'}) {
                $prefix = $case->{'label'}." (case #".$case->{'id'}."): ";
            }
            $self->{'result'}->{'returnmessage'} = $prefix.$self->{'result'}->{'returnmessage'};
            my $message = $self->{'result'}->{'returnmessage'};
            $message    = $message.' - '.$case->{errormessage} if defined $case->{errormessage};
            push @{$case->{'messages'}}, {
                'key'   => 'result-message',
                'value' => $message,
                'html'  => "<b><span class=\"fail\">FAILED :</span> ".$message."</b>"
            };
            $self->_out("TEST CASE FAILED : ".$message."\n");
        }
        # print regular error output
        elsif ( $case->{errormessage} ) {       # Add defined error message to the output
            push @{$case->{'messages'}}, {
                'key'   => 'result-message',
                'value' => $case->{errormessage},
                'html'  => "<b><span class=\"fail\">FAILED :</span> ".$case->{errormessage}."</b>"
            };
            $self->_out(qq|TEST CASE FAILED : $case->{errormessage}\n|);
        }
        else {
            push @{$case->{'messages'}}, {
                'key'   => 'result-message',
                'value' => 'TEST CASE FAILED',
                'html'  => "<b><span class=\"fail\">FAILED</span></b>"
            };
            $self->_out(qq|TEST CASE FAILED\n|);
        }
        unless( $self->{'result'}->{'returnmessage'} ) { #(used for plugin compatibility) if it's the first error message, set it to variable
            if( $case->{errormessage} ) {
                $self->{'result'}->{'returnmessage'} = $case->{errormessage};
            }
            else {
                $self->{'result'}->{'returnmessage'} = "Test case number ".$case->{'id'}." failed";
                if(defined $case->{'label'}) {
                    $self->{'result'}->{'returnmessage'} = "Test case ".$case->{'label'}." (#".$case->{'id'}.") failed";
                }
            }
        }
        if( $self->{'gui'} ) {
            $self->_gui_status_failed();
        }
    }
    elsif($case->{'iswarning'}) {
        # end result will be also warning
        $self->{'result'}->{'iswarning'} = 1;

        push @{$case->{'messages'}}, {'key' => 'success', 'value' => 'false' };
        if( $case->{errormessage} ) {       # Add defined error message to the output
            push @{$case->{'messages'}}, {'key' => 'result-message', 'value' => $case->{errormessage}, 'html' => "<b><span class=\"fail\">WARNED :</span> ".$case->{errormessage}."</b>" };
            $self->_out(qq|TEST CASE WARNED : $case->{errormessage}\n|);
        }
        # print regular error output
        else {
            # we suppress most logging when running in a plugin mode
            push @{$case->{'messages'}}, {'key' => 'result-message', 'value' => 'TEST CASE WARNED', 'html' => "<b><span class=\"fail\">WARNED</span></b>" };
            $self->_out(qq|TEST CASE WARNED\n|);
        }
        unless( $self->{'result'}->{'returnmessage'} ) { #(used for plugin compatibility) if it's the first error message, set it to variable
            if( $case->{errormessage} ) {
                $self->{'result'}->{'returnmessage'} = $case->{errormessage};
            }
            else {
                $self->{'result'}->{'returnmessage'} = "Test case number ".$case->{'id'}." warned";
                if(defined $case->{'label'}) {
                    $self->{'result'}->{'returnmessage'} = "Test case ".$case->{'label'}." (#".$case->{'id'}.") warned";
                }
            }

        }
        if( $self->{'gui'} ) {
            $self->_gui_status_failed();
        }
    }
    else {
        $self->_out(qq|TEST CASE PASSED\n|);
        push @{$case->{'messages'}}, {'key' => 'success', 'value' => 'true' };
        push @{$case->{'messages'}}, {
            'key' => 'result-message',
            'value' => 'TEST CASE PASSED',
            'html' => "<b><span class=\"pass\">PASSED</span></b>"
        };
        if( $self->{'gui'} ) {
            $self->_gui_status_passed();
        }
    }

    if( $self->{'gui'} ) { $self->_gui_timer_output($latency); }

    $self->_out(qq|Response Time = $latency sec \n|);
    $self->_out(qq|------------------------------------------------------- \n|);
    push @{$case->{'messages'}}, {
        'key' => 'responsetime',
        'value' => $latency,
        'html' => "<br />".$latency." sec </td>\n" };

    $self->{'result'}->{'runcount'}++;
    $self->{'result'}->{'totalruncount'}++;

    if( $self->{'gui'} ) {
        # update the statusbar
        $self->_gui_statusbar();
    }

    if( $latency > $self->{'result'}->{'maxresponse'} ) {
        # set max response time
        $self->{'result'}->{'maxresponse'} = $latency;
    }
    if(!defined $self->{'result'}->{'minresponse'} or $latency < $self->{'result'}->{'minresponse'} ) {
        # set min response time
        $self->{'result'}->{'minresponse'} = $latency;
    }
    # keep total of response times for calculating avg
    $self->{'result'}->{'totalresponse'} = ( $self->{'result'}->{'totalresponse'} + $latency );
    # avg response rounded to thousands
    $self->{'result'}->{'avgresponse'} = ( int( 1000 * ( $self->{'result'}->{'totalresponse'} / $self->{'result'}->{'totalruncount'} ) ) / 1000 );

    if( $self->{'gui'} ) {
        # update timers and counts in monitor tab
        $self->_gui_updatemonstats();
    }


    # if a sleep value is set in the test case, sleep that amount
    if( $case->{sleep} ) {
        sleep( $case->{sleep} );
    }

    $self->{'result'}->{'totalpassedcount'} += $case->{'passedcount'};
    $self->{'result'}->{'totalfailedcount'} += $case->{'failedcount'};

    if($case->{'iscritical'} or $case->{'iswarning'}) {
        $self->{'result'}->{'totalcasesfailedcount'}++;
    } else {
        $self->{'result'}->{'totalcasespassedcount'}++;
    }

    return $case;
}

################################################################################
sub _get_useragent {
    my $self = shift;

    # construct LWP object
    my $useragent  = LWP::UserAgent->new;

    # store cookies in our LWP object
    my($fh, $cookietempfilename) = tempfile(undef, UNLINK => 1);
    unlink ($cookietempfilename);
    $useragent->cookie_jar(HTTP::Cookies->new(
                                                 file     => $cookietempfilename,
                                                 autosave => 1,
                                              ));

    # http useragent that will show up in webserver logs
    unless(defined $self->{'config'}->{'useragent'}) {
        $useragent->agent('WebInject');
    } else {
        $useragent->agent($self->{'config'}->{'useragent'});
    }

    # add proxy support if it is set in config.xml
    if( $self->{'config'}->{'proxy'} ) {
        my $proxy = $self->{'config'}->{'proxy'};
        $proxy    =~ s/^http:\/\///mx;
        $useragent->proxy([qw( http )], "http://".$proxy);
        $ENV{'HTTPS_PROXY'} = "http://".$proxy;
    }

    # don't follow redirects unless set by config
    push @{$useragent->requests_redirectable}, 'POST';
    $useragent->max_redirect($self->{'config'}->{'max_redirect'});

    # add http basic authentication support
    # corresponds to:
    # $useragent->credentials('servername:portnumber', 'realm-name', 'username' => 'password');
    if(scalar @{$self->{'config'}->{'httpauth'}}) {
        # add the credentials to the user agent here. The foreach gives the reference to the tuple ($elem), and we
        # deref $elem to get the array elements.
        for my $elem ( @{ $self->{'config'}->{'httpauth'} } ) {
            #print "adding credential: $elem->[0]:$elem->[1], $elem->[2], $elem->[3] => $elem->[4]\n";
            $useragent->credentials( $elem->[0].":".$elem->[1], $elem->[2], $elem->[3] => $elem->[4] );
        }
    }

    # change response delay timeout in seconds if it is set in config.xml
    if($self->{'config'}->{'timeout'}) {
        $useragent->timeout($self->{'config'}->{'timeout'});    # default LWP timeout is 180 secs.
    }

    return $useragent;
}

################################################################################
# set defaults
sub _set_defaults {
    my $self = shift;
    $self->{'config'}             = {
        'currentdatetime'           => scalar localtime time,    #get current date and time for results report
        'standaloneplot'            => 'off',
        'graphtype'                 => 'lines',
        'httpauth'                  => [],
        'reporttype'                => 'standard',
        'output_dir'                => './',
        'nooutput'                  => undef,
        'baseurl'                   => '',
        'baseurl1'                  => '',
        'baseurl2'                  => '',
        'break_on_errors'           => 0,
        'max_redirect'              => 0,
        'globalhttplog'             => 'no',
        'proxy'                     => '',
        'timeout'                   => 180,
    };
    $self->{'exit_codes'}         = {
        'UNKNOWN'  => 3,
        'OK'       => 0,
        'WARNING'  => 1,
        'CRITICAL' => 2,
    };
    $self->{'switches'}           = {
        'stop'                      => 'no',
        'plotclear'                 => 'no',
    };
    $self->{'out'}                = '';
    $self->_reset_result();
    return;
}

################################################################################
# reset result
sub _reset_result {
    my $self = shift;
    $self->{'result'}         = {
        'cases'                  => [],
        'returnmessage'          => undef,
        'totalcasesfailedcount'  => 0,
        'totalcasespassedcount'  => 0,
        'totalfailedcount'       => 0,
        'totalpassedcount'       => 0,
        'totalresponse'          => 0,
        'totalruncount'          => 0,
        'totalruntime'           => 0,
        'casecount'              => 0,
        'avgresponse'            => 0,
        'iscritical'             => 0,
        'iswarning'              => 0,
        'maxresponse'            => 0,
        'minresponse'            => undef,
        'runcount'               => 0,
    };
    return;
}

################################################################################
# write initial text for STDOUT
sub _writeinitialstdout {
    my $self = shift;

    if($self->{'config'}->{'reporttype'} !~ /^nagios/mx) {
        $self->_out(qq|
Starting WebInject Engine (v$Webinject::VERSION)...
|);
    }
    $self->_out("-------------------------------------------------------\n");
    return;
}

################################################################################
# write summary and closing tags for results file
sub _write_result_html {
    my $self    = shift;

    my $file = $self->{'config'}->{'output_dir'}."results.html";
    open( my $resultshtml, ">", $file )
      or $self->_usage("ERROR: Failed to write ".$file.": ".$!);

    print $resultshtml
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
        table, td {
            border:  solid #ddd 1px;
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
<table>
<tr>
<th>Test</th>
<th>Description<br />Request URL</th>
<th>Results</th>
<th>Summary<br />Response Time</th>
</tr>
|;
    for my $file (@{$self->{'result'}->{'files'}}) {
        for my $case (@{$file->{'cases'}}) {
            print $resultshtml qq|<tr><td>$file->{'name'}<br /><b>$case->{'id'} </b></td>\n|;
            for my $message (@{$case->{'messages'}}) {
                next unless defined $message->{'html'};
                print $resultshtml $message->{'html'} . "\n";
            }
            print $resultshtml "</tr>\n";
        }
    }

    print $resultshtml qq|
</table>
<b>
Start Time: $self->{'config'}->{'currentdatetime'} <br />
Total Run Time: $self->{'result'}->{'totalruntime'} seconds <br />
<br />
Test Cases Run: $self->{'result'}->{'totalruncount'} <br />
Test Cases Passed: $self->{'result'}->{'totalcasespassedcount'} <br />
Test Cases Failed: $self->{'result'}->{'totalcasesfailedcount'} <br />
Verifications Passed: $self->{'result'}->{'totalpassedcount'} <br />
Verifications Failed: $self->{'result'}->{'totalfailedcount'} <br />
<br />
Average Response Time: $self->{'result'}->{'avgresponse'} seconds <br />
Max Response Time: $self->{'result'}->{'maxresponse'} seconds <br />
Min Response Time: $self->{'result'}->{'minresponse'} seconds <br />
</b>
<br />

</body>
</html>
|;
    close($resultshtml);
    return;
}

################################################################################
# write summary and closing tags for XML results file
sub _write_result_xml {
    my $self    = shift;

    my $file = $self->{'config'}->{'output_dir'}."results.xml";
    open( my $resultsxml, ">", $file )
      or $self->_usage("ERROR: Failed to write ".$file.": ".$!);

    print $resultsxml "<results>\n\n";

    for my $file (@{$self->{'result'}->{'files'}}) {
        print $resultsxml "    <testcases file=\"".$file->{'name'}."\">\n\n";
        for my $case (@{$file->{'cases'}}) {
            print $resultsxml "        <testcase id=\"".$case->{'id'}."\">\n";
            for my $message (@{$case->{'messages'}}) {
                next unless defined $message->{'key'};
                print $resultsxml "            <".$message->{'key'}.">".$message->{'value'}."</".$message->{'key'}.">\n";
            }
            print $resultsxml "        </testcase>\n\n";
        }
        print $resultsxml "    </testcases>\n";
    }

    print $resultsxml qq|
    <test-summary>
        <start-time>$self->{'config'}->{'currentdatetime'}</start-time>
        <total-run-time>$self->{'result'}->{'totalruntime'}</total-run-time>
        <test-cases-run>$self->{'result'}->{'totalruncount'}</test-cases-run>
        <test-cases-passed>$self->{'result'}->{'totalcasespassedcount'}</test-cases-passed>
        <test-cases-failed>$self->{'result'}->{'totalcasesfailedcount'}</test-cases-failed>
        <verifications-passed>$self->{'result'}->{'totalpassedcount'}</verifications-passed>
        <verifications-failed>$self->{'result'}->{'totalfailedcount'}</verifications-failed>
        <average-response-time>$self->{'result'}->{'avgresponse'}</average-response-time>
        <max-response-time>$self->{'result'}->{'maxresponse'}</max-response-time>
        <min-response-time>$self->{'result'}->{'minresponse'}</min-response-time>
    </test-summary>

</results>
|;
    close($resultsxml);
    return;
}

################################################################################
# write summary and closing text for STDOUT
sub _writefinalstdout {
    my $self = shift;

    if($self->{'config'}->{'reporttype'} !~ /^nagios/mx) {
        $self->_out(qq|
Start Time: $self->{'config'}->{'currentdatetime'}
Total Run Time: $self->{'result'}->{'totalruntime'} seconds

|);
    }

    $self->_out(qq|
Test Cases Run: $self->{'result'}->{'totalruncount'}
Test Cases Passed: $self->{'result'}->{'totalcasespassedcount'}
Test Cases Failed: $self->{'result'}->{'totalcasesfailedcount'}
Verifications Passed: $self->{'result'}->{'totalpassedcount'}
Verifications Failed: $self->{'result'}->{'totalfailedcount'}

|);
    return;
}

################################################################################
sub _http_defaults {
    my $self      = shift;
    my $request   = shift;
    my $useragent = shift;
    my $case      = shift;

    # add an additional HTTP Header if specified
    if($case->{'addheader'}) {
        # can add multiple headers with a pipe delimiter
        for my $addheader (split /\|/mx, $case->{'addheader'}) {
            $addheader =~ m~(.*):\ (.*)~mx;
            $request->header( $1 => $2 );   # using HTTP::Headers Class
        }
    }

    # print $self->{'request'}->as_string; print "\n\n";

    my $starttimer        = time();
    my $response          = $useragent->request($request);
    my $endtimer          = time();
    my $latency           = ( int( 1000 * ( $endtimer - $starttimer ) ) / 1000 ); # elapsed time rounded to thousandths
    # print $response->as_string; print "\n\n";

    return($latency,$request,$response);
}

################################################################################
# send http request and read response
sub _httpget {
    my $self      = shift;
    my $useragent = shift;
    my $case      = shift;

    $self->_out("GET Request: ".$case->{url}."\n");
    my $request = new HTTP::Request( 'GET', $case->{url} );
    return $self->_http_defaults($request, $useragent, $case);
}

################################################################################
# post request based on specified encoding
sub _httppost {
    my $self        = shift;
    my $useragent   = shift;
    my $case        = shift;

    if($case->{posttype} ) {
        if($case->{posttype} =~ m~application/x\-www\-form\-urlencoded~mx) {
            return $self->_httppost_form_urlencoded($useragent, $case);
        }
        elsif($case->{posttype} =~ m~multipart/form\-data~mx) {
            return $self->_httppost_form_data($useragent, $case);
        }
        elsif(   ($case->{posttype} =~ m~text/xml~mx)
              or ($case->{posttype} =~ m~application/soap\+xml~mx)
             )
        {
            return $self->_httppost_xml($useragent, $case);
        }
        else {
            $self->_usage('ERROR: Bad Form Encoding Type, I only accept "application/x-www-form-urlencoded", "multipart/form-data", "text/xml", "application/soap+xml"');
        }
    }
    else {
        # use "x-www-form-urlencoded" if no encoding is specified
        $case->{posttype} = 'application/x-www-form-urlencoded';
        return $self->_httppost_form_urlencoded($useragent, $case);
    }
    return;
}

################################################################################
# send application/x-www-form-urlencoded HTTP request and read response
sub _httppost_form_urlencoded {
    my $self      = shift;
    my $useragent = shift;
    my $case      = shift;

    $self->_out("POST Request: ".$case->{url}."\n");
    my $request = new HTTP::Request('POST', $case->{url} );
    $request->content_type($case->{posttype});
    $request->content($case->{postbody});

    return $self->_http_defaults($request,$useragent, $case);
}

################################################################################
# send text/xml HTTP request and read response
sub _httppost_xml {
    my $self        = shift;
    my $useragent   = shift;
    my $case        = shift;

    my($latency,$request,$response);

    # read the xml file specified in the testcase
    $case->{postbody} =~ m~file=>(.*)~imx;
    open( my $xmlbody, "<", $1 ) or $self->_usage("ERROR: Failed to open text/xml file ".$1.": ".$!);    # open file handle
    my @xmlbody = <$xmlbody>;    # read the file into an array
    close($xmlbody);

    $self->_out("POST Request: ".$case->{url}."\n");
    $request = new HTTP::Request( 'POST', $case->{url} );
    $request->content_type($case->{posttype});
    $request->content( join( " ", @xmlbody ) );    # load the contents of the file into the request body

    ($latency,$request,$response) = $self->_http_defaults($request, $useragent, $case);

    my $xmlparser = new XML::Parser;
    # see if the XML parses properly
    try {
        $xmlparser->parse($response->decoded_content);

        # print "good xml\n";
        push @{$case->{'messages'}}, {'key' => 'verifyxml-success', 'value' => 'true', 'html' => '<span class="pass">Passed XML Parser (content is well-formed)</span>' };
        $self->_out("Passed XML Parser (content is well-formed) \n");
        $case->{'passedcount'}++;

        # exit try block
        return;
    }
    catch Error with {
        # get the exception object
        my $ex = shift;
        # print "bad xml\n";
        # we suppress most logging when running in a plugin mode
        if($self->{'config'}->{'reporttype'} eq 'standard') {
            push @{$case->{'messages'}}, {'key' => 'verifyxml-success', 'value' => 'false', 'html' => "<span class=\"fail\">Failed XML parser on response:</span> ".$ex };
        }
        $self->_out("Failed XML parser on response: $ex \n");
        $case->{'failedcount'}++;
        $case->{'iscritical'} = 1;
    };    # <-- remember the semicolon

    return($latency,$request,$response);
}

################################################################################
# send multipart/form-data HTTP request and read response
sub _httppost_form_data {
    my $self      = shift;
    my $useragent = shift;
    my $case      = shift;
    my %myContent_;
    ## no critic
    eval "\%myContent_ = $case->{postbody}";
    ## use critic

    $self->_out("POST Request: ".$case->{url}."\n");
    my $request = POST($case->{url},
                       Content_Type => $case->{posttype},
                       Content      => \%myContent_);

    return $self->_http_defaults($request, $useragent, $case);
}

################################################################################
# do verification of http response and print status to HTML/XML/STDOUT/UI
sub _verify {
    my $self        = shift;
    my $response    = shift;
    my $case        = shift;

    confess("no response") unless defined $response;
    confess("no case")     unless defined $case;

    if( $case->{verifyresponsecode} ) {
        $self->_out(qq|Verify Response Code: "$case->{verifyresponsecode}" \n|);
        push @{$case->{'messages'}}, {'key' => 'verifyresponsecode', 'value' => $case->{verifyresponsecode} };

        # verify returned HTTP response code matches verifyresponsecode set in test case
        if ( $case->{verifyresponsecode} == $response->code() ) {
            push @{$case->{'messages'}}, {'key' => 'verifyresponsecode-success', 'value' => 'true', 'html' => '<span class="pass">Passed HTTP Response Code:</span> '.$case->{verifyresponsecode} };
            push @{$case->{'messages'}}, {'key' => 'verifyresponsecode-messages', 'value' => 'Passed HTTP Response Code Verification' };
            $self->_out(qq|Passed HTTP Response Code Verification \n|);
            $case->{'passedcount'}++;
        }
        else {
            push @{$case->{'messages'}}, {'key' => 'verifyresponsecode-success', 'value' => 'false', 'html' => '<span class="fail">Failed HTTP Response Code:</span> received '.$response->code().', expecting '.$case->{verifyresponsecode} };
            push @{$case->{'messages'}}, {'key' => 'verifyresponsecode-messages', 'value' => 'Failed HTTP Response Code Verification (received '.$response->code().', expecting '.$case->{verifyresponsecode}.')' };
            $self->_out(qq|Failed HTTP Response Code Verification (received |.$response->code().qq|, expecting $case->{verifyresponsecode}) \n|);
            $case->{'failedcount'}++;
            $case->{'iscritical'} = 1;

            if($self->{'config'}->{'break_on_errors'}) {
                $self->{'result'}->{'returnmessage'} = 'Failed HTTP Response Code Verification (received '.$response->code().', expecting '.$case->{verifyresponsecode}.')';
                return;
            }
        }
    }
    else {
        # verify http response code is in the 100-399 range
        if($response->as_string() =~ /HTTP\/1.(0|1)\ (1|2|3)/imx ) {     # verify existance of string in response
            push @{$case->{'messages'}}, {'key' => 'verifyresponsecode-success', 'value' => 'true', 'html' => '<span class="pass">Passed HTTP Response Code Verification (not in error range)</span>' };
            push @{$case->{'messages'}}, {'key' => 'verifyresponsecode-messages', 'value' => 'Passed HTTP Response Code Verification (not in error range)' };
            $self->_out(qq|Passed HTTP Response Code Verification (not in error range) \n|);

            # succesful response codes: 100-399
            $case->{'passedcount'}++;
        }
        else {
            $response->as_string() =~ /(HTTP\/1.)(.*)/mxi;
            if($1) {    #this is true if an HTTP response returned
                push @{$case->{'messages'}}, {'key' => 'verifyresponsecode-success', 'value' => 'false', 'html' => '<span class="fail">Failed HTTP Response Code Verification ('.$1.$2.')</span>' };
                push @{$case->{'messages'}}, {'key' => 'verifyresponsecode-messages', 'value' => 'Failed HTTP Response Code Verification ('.$1.$2.')' };
                $self->_out("Failed HTTP Response Code Verification ($1$2) \n");    #($1$2) is HTTP response code

                $case->{'failedcount'}++;
                $case->{'iscritical'} = 1;

                if($self->{'config'}->{'break_on_errors'}) {
                    $self->{'result'}->{'returnmessage'} = 'Failed HTTP Response Code Verification ('.$1.$2.')';
                    return;
                }
            }
            #no HTTP response returned.. could be error in connection, bad hostname/address, or can not connect to web server
            else
            {
                push @{$case->{'messages'}}, {'key' => 'verifyresponsecode-success', 'value' => 'false', 'html' => '<span class="fail">Failed - No Response</span>' };
                push @{$case->{'messages'}}, {'key' => 'verifyresponsecode-messages', 'value' => 'Failed - No Response' };
                $self->_out("Failed - No valid HTTP response:\n".$response->as_string());

                $case->{'failedcount'}++;
                $case->{'iscritical'} = 1;

                if($self->{'config'}->{'break_on_errors'}) {
                    $self->{'result'}->{'returnmessage'} = 'Failed - No valid HTTP response: '.$response->as_string();
                    return;
                }
            }
        }
    }
    push @{$case->{'messages'}}, { 'html' => '<br />' };

    for my $nr ('', 1..1000) {
        my $key = "verifypositive".$nr;
        if( $case->{$key} ) {
            $self->_out("Verify: '".$case->{$key}."' \n");
            push @{$case->{'messages'}}, {'key' => $key, 'value' => $case->{$key} };
            my $regex = $self->_fix_regex($case->{$key});
            # verify existence of string in response
            if( $response->as_string() =~ m~$regex~simx ) {
                push @{$case->{'messages'}}, {'key' => $key.'-success', 'value' => 'true', 'html' => "<span class=\"pass\">Passed:</span> ".$case->{$key} };
                $self->_out("Passed Positive Verification \n");
                $case->{'passedcount'}++;
            }
            else {
                push @{$case->{'messages'}}, {'key' => $key.'-success', 'value' => 'false', 'html' => "<span class=\"fail\">Failed:</span> ".$case->{$key} };
                $self->_out("Failed Positive Verification \n");
                $case->{'failedcount'}++;
                $case->{'iscritical'} = 1;

                if($self->{'config'}->{'break_on_errors'}) {
                    $self->{'result'}->{'returnmessage'} = 'Failed Positive Verification, can not find a string matching regex: '.$regex;
                    return;
                }
            }
            push @{$case->{'messages'}}, { 'html' => '<br />' };
        }
        elsif($nr ne '' and $nr > 5) {
            last;
        }
    }

    for my $nr ('', 1..1000) {
        my $key = "verifynegative".$nr;
        if( $case->{$key} ) {
            $self->_out("Verify Negative: '".$case->{$key}."' \n");
            push @{$case->{'messages'}}, {'key' => $key, 'value' => $case->{$key} };
            my $regex = $self->_fix_regex($case->{$key});
            # verify existence of string in response
            if( $response->as_string() =~ m~$regex~simx ) {
                push @{$case->{'messages'}}, {'key' => $key.'-success', 'value' => 'false', 'html' => '<span class="fail">Failed Negative:</span> '.$case->{$key} };
                $self->_out("Failed Negative Verification \n");
                $case->{'failedcount'}++;
                $case->{'iscritical'} = 1;

                if($self->{'config'}->{'break_on_errors'}) {
                    $self->{'result'}->{'returnmessage'} = 'Failed Negative Verification, found regex matched string: '.$regex;
                    return;
                }
            }
            else {
                push @{$case->{'messages'}}, {'key' => $key.'-success', 'value' => 'true', 'html' => '<span class="pass">Passed Negative:</span> '.$case->{$key} };
                $self->_out("Passed Negative Verification \n");
                $case->{'passedcount'}++;
            }
            push @{$case->{'messages'}}, { 'html' => '<br />' };
        }
        elsif($nr ne '' and $nr > 5) {
            last;
        }
    }

    if($self->{'verifylater'}) {
        my $regex = $self->_fix_regex($self->{'verifylater'});
        # verify existence of string in response
        if($response->as_string() =~ m~$regex~simx ) {
            push @{$case->{'messages'}}, {'key' => 'verifypositivenext-success', 'value' => 'true', 'html' => '<span class="pass">Passed Positive Verification (verification set in previous test case)</span>' };
            $self->_out("Passed Positive Verification (verification set in previous test case) \n");
            $case->{'passedcount'}++;
        }
        else {
            push @{$case->{'messages'}}, {'key' => 'verifypositivenext-success', 'value' => 'false', 'html' => '<span class="fail">Failed Positive Verification (verification set in previous test case)</span>' };
            $self->_out("Failed Positive Verification (verification set in previous test case) \n");
            $case->{'failedcount'}++;
            $case->{'iscritical'} = 1;

            if($self->{'config'}->{'break_on_errors'}) {
                $self->{'result'}->{'returnmessage'} = 'Failed Positive Verification (verification set in previous test case), can not find a string matching regex: '.$regex;
                return;
            }
        }
        push @{$case->{'messages'}}, { 'html' => '<br />' };
        # set to null after verification
        delete $self->{'verifylater'};
    }

    if($self->{'verifylaterneg'}) {
        my $regex = $self->_fix_regex($self->{'verifylaterneg'});
        # verify existence of string in response
        if($response->as_string() =~ m~$regex~simx) {
            push @{$case->{'messages'}}, {'key' => 'verifynegativenext-success', 'value' => 'false', 'html' => '<span class="fail">Failed Negative Verification (negative verification set in previous test case)</span>' };
            $self->_out("Failed Negative Verification (negative verification set in previous test case) \n");
            $case->{'failedcount'}++;
            $case->{'iscritical'} = 1;

            if($self->{'config'}->{'break_on_errors'}) {
                $self->{'result'}->{'returnmessage'} = 'Failed Negative Verification (negative verification set in previous test case), found regex matched string: '.$regex;
                return;
            }
        }
        else {
            push @{$case->{'messages'}}, {'key' => 'verifynegativenext-success', 'value' => 'true', 'html' => '<span class="pass">Passed Negative Verification (negative verification set in previous test case)</span>' };
            $self->_out("Passed Negative Verification (negative verification set in previous test case) \n");
            $case->{'passedcount'}++;
        }
        push @{$case->{'messages'}}, { 'html' => '<br />' };
        # set to null after verification
        delete $self->{'verifylaterneg'};
    }

    if($case->{'warning'}) {
        $self->_out("Verify Warning Threshold: ".$case->{'warning'}."\n");
        push @{$case->{'messages'}}, {'key' => "Warning Threshold", 'value' => $case->{''} };
        if($case->{'latency'} > $case->{'warning'}) {
            push @{$case->{'messages'}}, {'key' => 'warning-success', 'value' => 'false', 'html' => "<span class=\"fail\">Failed Warning Threshold:</span> ".$case->{'warning'} };
            $self->_out("Failed Warning Threshold \n");
            $case->{'failedcount'}++;
            $case->{'iswarning'} = 1;
        }
        else {
            $self->_out("Passed Warning Threshold \n");
            push @{$case->{'messages'}}, {'key' => 'warning-success', 'value' => 'true', 'html' => "<span class=\"pass\">Passed Warning Threshold:</span> ".$case->{'warning'} };
            $case->{'passedcount'}++;
        }
        push @{$case->{'messages'}}, { 'html' => '<br />' };
    }

    if($case->{'critical'}) {
        $self->_out("Verify Critical Threshold: ".$case->{'critical'}."\n");
        push @{$case->{'messages'}}, {'key' => "Critical Threshold", 'value' => $case->{''} };
        if($case->{'latency'} > $case->{'critical'}) {
            push @{$case->{'messages'}}, {'key' => 'critical-success', 'value' => 'false', 'html' => "<span class=\"fail\">Failed Critical Threshold:</span> ".$case->{'critical'} };
            $self->_out("Failed Critical Threshold \n");
            $case->{'failedcount'}++;
            $case->{'iscritical'} = 1;
        }
        else {
            $self->_out("Passed Critical Threshold \n");
            push @{$case->{'messages'}}, {'key' => 'critical-success', 'value' => 'true', 'html' => "<span class=\"pass\">Passed Critical Threshold:</span> ".$case->{'critical'} };
            $case->{'passedcount'}++;
        }
    }

    return;
}

################################################################################
# parse values from responses for use in future request (for session id's, dynamic URL rewriting, etc)
sub _parseresponse {
    my $self     = shift;
    my $response = shift;
    my $case     = shift;

    my ( $resptoparse, @parseargs );
    my ( $leftboundary, $rightboundary, $escape );

    for my $type ( qw/parseresponse parseresponse1 parseresponse2 parseresponse3 parseresponse4 parseresponse5/ ) {

        next unless $case->{$type};

        @parseargs = split( /\|/mx, $case->{$type} );

        $leftboundary  = $parseargs[0];
        $rightboundary = $parseargs[1];
        $escape        = $parseargs[2];

        $resptoparse = $response->as_string;
        ## no critic
        if ( $resptoparse =~ m~$leftboundary(.*?)$rightboundary~s ) {
            $self->{'parsedresult'}->{$type} = $1;
        }
        ## use critic
        else {
            push @{$case->{'messages'}}, {'key' => $type.'-success', 'value' => 'false', 'html' => "<span class=\"fail\">Failed Parseresult, cannot find</span> $leftboundary(.*?)$rightboundary" };
            $self->_out("Failed Parseresult, cannot find $leftboundary(*)$rightboundary\n");
            $case->{'iswarning'} = 1;
        }

        if ($escape) {
            if ( $escape eq 'escape' ) {
                $self->{'parsedresult'}->{$type} =
                  $self->_url_escape( $self->{'parsedresult'}->{$type} );
            }
        }

        #print "\n\nParsed String: $self->{'parsedresult'}->{$type}\n\n";
    }
    return;
}

################################################################################
# read config.xml
sub _read_config_xml {
    my $self        = shift;
    my $config_file = shift;

    my($config, $comment_mode,@configlines);

    # process the config file
    # if -c option was set on command line, use specified config file
    if(defined $config_file) {
        open( $config, '<', $config_file )
          or $self->_usage("ERROR: Failed to open ".$config_file." file: ".$!);
        $self->{'config'}->{'exists'} = 1;   # flag we are going to use a config file
    }
    # if config.xml exists, read it
    elsif( -e "config.xml" ) {
        open( $config, '<', "config.xml" )
          or $self->_usage("ERROR: Failed to open config.xml file: ".$!);
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
                    push( @configlines, $_ );
                }
            }
        }
        close($config);
    }

    #grab values for constants in config file:
    foreach (@configlines) {

        for my $key (
            qw/baseurl baseurl1 baseurl2 gnuplot proxy timeout output_dir
            globaltimeout globalhttplog standaloneplot max_redirect
            break_on_errors useragent/
          )
        {

            if (/<$key>/mx) {
                $_ =~ m~<$key>(.*)</$key>~mx;
                $self->{'config'}->{$key} = $1;

                #print "\n$_ : $self->{'config'}->{$_} \n\n";
            }
        }

        if (/<reporttype>/mx) {
            $_ =~ m~<reporttype>(.*)</reporttype>~mx;
            if ( $1 ne "standard" ) {
                $self->{'config'}->{'reporttype'} = $1;
                $self->{'config'}->{'nooutput'}   = "set";
            }

            #print "\nreporttype : $self->{'config'}->{'reporttype'} \n\n";
        }

        if (/<httpauth>/mx) {

            $_ =~ m~<httpauth>(.*)</httpauth>~mx;
            $self->_set_http_auth($1);

            #print "\nhttpauth : @{$self->{'config'}->{'httpauth'}} \n\n";
        }

        if(/<testcasefile>/mx) {
            my $firstparse = $';    #print "$' \n\n";
            $firstparse =~ m~</testcasefile>~mx;
            my $filename = $`;      #string between tags will be in $filename
            #print "\n$filename \n\n";
            push @{ $self->{'casefilelist'} }, $filename;         #add next filename we grab to end of array
        }
    }

    return;
}

################################################################################
# parse and set http auth config
sub _set_http_auth {
    my $self       = shift;
    my $confstring = shift;

    #each time we see an <httpauth>, we set @authentry to be the
    #array of values, then we use [] to get a reference to that array
    #and push that reference onto @httpauth.

    my @authentry = split( /:/mx, $confstring );
    if( scalar @authentry != 5 ) {
        $self->_usage("ERROR: httpauth should have 5 fields delimited by colons, got: ".$confstring);
    }
    else {
        push( @{ $self->{'config'}->{'httpauth'} }, [@authentry] );
    }
    # basic authentication only works with redirects enabled
    if($self->{'config'}->{'max_redirect'} == 0) {
        $self->{'config'}->{'max_redirect'}++;
    }

    return;
}

################################################################################
# get test case files to run (from command line or config file) and evaluate constants
sub _processcasefile {
    # parse config file and grab values it sets
    my $self = shift;

    if( ( $#ARGV + 1 ) < 1 ) {    #no command line args were passed
        unless( $self->{'casefilelist'}->[0] ) {
            if ( -e "testcases.xml" ) {
                # if no files are specified in config.xml, default to testcases.xml
                push @{ $self->{'casefilelist'} }, "testcases.xml";
            }
            else {
                $self->_usage("ERROR: I can't find any test case files to run.\nYou must either use a config file or pass a filename "
                  . "on the command line if you are not using the default testcase file (testcases.xml).");
            }
        }
    }

    elsif( ( $#ARGV + 1 ) == 1 ) {    # one command line arg was passed
        # use testcase filename passed on command line (config.xml is only used for other options)
        push @{ $self->{'casefilelist'} }, $ARGV[0]; # first commandline argument is the test case file, put this on the array for processing
    }

    elsif( ( $#ARGV + 1 ) == 2 ) {     # two command line args were passed
        my $xpath = $ARGV[1];
        if ( $xpath =~ /\/(.*)\[/mx ) {    # if the argument contains a "/" and "[", it is really an XPath
            $xpath =~ /(.*)\/(.*)\[(.*?)\]/mx;    #if it contains XPath info, just grab the file name
            $self->{'xnode'} = $3;    # grab the XPath Node value.. (from inside the "[]")
            # print "\nXPath Node is: $self->{'xnode'} \n";
        }
        else {
            $self->_usage("ERROR: Sorry, $xpath is not in the XPath format I was expecting, I'm ignoring it...");
        }

        # use testcase filename passed on command line (config.xml is only used for other options)
        push @{ $self->{'casefilelist'} }, $ARGV[0]; # first command line argument is the test case file, put this on the array for processing
    }

    elsif ( ( $#ARGV + 1 ) > 2 ) {    #too many command line args were passed
        $self->_usage("ERROR: Too many arguments.");
    }

    #print "\ntestcase file list: @{$self->{'casefilelist'}}\n\n";

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
    my $filename = $currentcasefile;
    open( my $xmltoconvert, '<', $filename )
      or $self->_usage("ERROR: Failed to read test case file: ".$filename.": ".$!);
    # read the file into an array
    @xmltoconvert = <$xmltoconvert>;
    my $ids = {};
    for my $line (@xmltoconvert) {

        # convert escaped chars and certain reserved chars to temporary values that the parser can handle
        # these are converted back later in processing
        $line =~ s/&/{AMPERSAND}/gmx;
        $line =~ s/\\</{LESSTHAN}/gmx;

        # convert variables to lowercase
        $line =~ s/(\$\{[\w\.]+\})/\L$1\E/gmx;
        $line =~ s/(varname=('|").*?('|"))/\L$1\E/gmx;

        # count cases while we are here
        if ( $line =~ /<case/mx ) {
            $self->{'result'}->{'casecount'}++;
        }

        # verify id is only use once per file
        if ( $line =~ /^\s*id\s*=\s*\"*(\d+)\"*/mx ) {
            if(defined $ids->{$1}) {
                $self->{'result'}->{'iswarning'} = 1;
                $self->_out("Warning: case id $1 is used more than once!\n");
            }
            $ids->{$1} = 1;
        }
    }

    close($xmltoconvert);

    # open file handle to temp file
    open( $xmltoconvert, '>', $tempfilename )
      or $self->_usage("ERROR: Failed to write ".$tempfilename.": ".$!);
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
    return $string;
}

################################################################################
# converts replaced xml with parsed result
sub _convertbackxmlresult {
    my ( $self, $string, $timestamp ) = @_;
    return unless defined $string;
    $string =~ s~\{PARSEDRESULT\}~$self->{'parsedresult'}->{'parseresponse'}~gmx if defined $self->{'parsedresult'}->{'parseresponse'};
    for my $x (1..5) {
        $string =~ s~\{PARSEDRESULT$x\}~$self->{'parsedresult'}->{"parseresponse$x"}~gmx if defined $self->{'parsedresult'}->{"parseresponse$x"};
    }
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
    my $response    = shift;
    my $case        = shift;
    my $output      = '';

    # http request - log setting per test case
    if($case->{'logrequest'} && $case->{'logrequest'} =~ /yes/mxi ) {
        $output .= $request->as_string."\n\n";
    }

    # http response - log setting per test case
    if($case->{'logresponse'} && $case->{'logresponse'} =~ /yes/mxi ) {
        $output .= $response->as_string."\n\n";
    }

    # global http log setting
    if($self->{'config'}->{'globalhttplog'} && $self->{'config'}->{'globalhttplog'} =~ /yes/mxi ) {
        $output .= $request->as_string."\n\n";
        $output .= $response->as_string."\n\n";
    }

    # global http log setting - onfail mode
    if($self->{'config'}->{'globalhttplog'} && $self->{'config'}->{'globalhttplog'} =~ /onfail/mxi && $case->{'iscritical'}) {
        $output .= $request->as_string."\n\n";
        $output .= $response->as_string."\n\n";
    }

    if($output ne '') {
        my $file = $self->{'config'}->{'output_dir'}."http.log";
        open( my $httplogfile, ">>", $file )
          or $self->_usage("ERROR: Failed to write ".$file.": ".$!);
        print $httplogfile $output;
        print $httplogfile "\n************************* LOG SEPARATOR *************************\n\n\n";
        close($httplogfile);
    }

    return;
}

################################################################################
# write performance results to plot.log in the format gnuplot can use
sub _plotlog {
    my ( $self, $value ) = @_;

    my ( %months, $date, $time, $mon, $mday, $hours, $min, $sec, $year );

    # do this unless: monitor is disabled in gui, or running standalone mode without config setting to turn on plotting
    if(   ( $self->{'gui'} and $self->{'monitorenabledchkbx'} ne 'monitor_off')
       or (!$self->{'gui'} and $self->{'config'}->{'standaloneplot'} eq 'on')
    ) {

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
        # used to clear the graph when requested
        if( $self->{'switches'}->{'plotclear'} eq 'yes' ) {
            # open in clobber mode so log gets truncated
            my $file = $self->{'config'}->{'output_dir'}."plot.log";
            open( $plotlog, '>', $file )
              or $self->_usage("ERROR: Failed to write ".$file.": ".$!);
            $self->{'switches'}->{'plotclear'} = 'no';    # reset the value
        }
        else {
            my $file = $self->{'config'}->{'output_dir'}."plot.log";
            open( $plotlog, '>>', $file )
              or $self->_usage("ERROR: Failed to write ".$file.": ".$!);  #open in append mode
        }

        printf $plotlog "%s %2.4f\n", $time, $value;
        close($plotlog);
    }
    return;
}

################################################################################
# create gnuplot config file
sub _plotcfg {
    my $self = shift;

    # do this unless: monitor is disabled in gui, or running standalone mode without config setting to turn on plotting
    if(   ( $self->{'gui'} and $self->{'monitorenabledchkbx'} ne 'monitor_off')
       or (!$self->{'gui'} and $self->{'config'}->{'standaloneplot'} eq 'on')
    ) {
        my $file = $self->{'config'}->{'output_dir'}."plot.plt";
        open( my $gnuplotplt, ">", $file )
          or _usage("ERROR: Could not open ".$file.": ".$!);
        print $gnuplotplt qq|
set term png
set output \"$self->{'config'}->{'output_dir'}plot.png\"
set size 1.1,0.5
set pointsize .5
set xdata time
set ylabel \"Response Time (seconds)\"
set yrange [0:]
set bmargin 2
set tmargin 2
set timefmt \"%m %d %H %M %S %Y\"
plot \"$self->{'config'}->{'output_dir'}plot.log\" using 1:7 title \"Response Times" w $self->{'config'}->{'graphtype'}
|;
        close($gnuplotplt);

    }
    return;
}

################################################################################
# do ending tasks
sub _finaltasks {
    my $self        = shift;

    if ( $self->{'gui'} ) { $self->_gui_stop(); }

    # we suppress most logging when running in a plugin mode
    if($self->{'config'}->{'reporttype'} eq 'standard') {
        # write summary and closing tags for results file
        $self->_write_result_html();

        #write summary and closing tags for XML results file
        $self->_write_result_xml();
    }

    # write summary and closing tags for STDOUT
    $self->_writefinalstdout();

    #plugin modes
    if($self->{'config'}->{'reporttype'} ne 'standard') {
        # return value is set which corresponds to a monitoring program
        # Nagios plugin compatibility
        if($self->{'config'}->{'reporttype'} =~ /^nagios/mx) {
            # nagios perf data has following format
            # 'label'=value[UOM];[warn];[crit];[min];[max]
            my $crit = 0;
            if(defined $self->{'config'}->{globaltimeout}) {
                $crit = $self->{'config'}->{globaltimeout};
            }
            my $lastid = 0;
            my $perfdata = '|time='.$self->{'result'}->{'totalruntime'}.';0;'.$crit.';0;0';
            for my $file (@{$self->{'result'}->{'files'}}) {
                for my $case (@{$file->{'cases'}}) {
                    my $warn   = $case->{'warning'}  || 0;
                    my $crit   = $case->{'critical'} || 0;
                    my $label  = $case->{'label'}    || 'case'.$case->{'id'};
                    $perfdata .= ' '.$label.'='.$case->{'latency'}.';'.$warn.';'.$crit.';0;0';
                    $lastid = $case->{'id'};
                }
            }
            # report performance data for missed cases too
            for my $nr (1..($self->{'result'}->{'casecount'} - $self->{'result'}->{'totalruncount'})) {
                $lastid++;
                my $label  = 'case'.$lastid;
                $perfdata .= ' '.$label.'=0;0;0;0;0';
            }

            my($rc,$message);
            if($self->{'result'}->{'iscritical'}) {
                $message = "WebInject CRITICAL - ".$self->{'result'}->{'returnmessage'};
                $rc      = $self->{'exit_codes'}->{'CRITICAL'};
            }
            elsif($self->{'result'}->{'iswarning'}) {
                $message = "WebInject WARNING - ".$self->{'result'}->{'returnmessage'};
                $rc      = $self->{'exit_codes'}->{'WARNING'};
            }
            elsif( $self->{'config'}->{globaltimeout} && $self->{'result'}->{'totalruntime'} > $self->{'config'}->{globaltimeout} ) {
                $message = "WebInject WARNING - All tests passed successfully but global timeout (".$self->{'config'}->{globaltimeout}." seconds) has been reached";
                $rc      = $self->{'exit_codes'}->{'WARNING'};
            }
            else {
                $message = "WebInject OK - All tests passed successfully in ".$self->{'result'}->{'totalruntime'}." seconds";
                $rc      = $self->{'exit_codes'}->{'OK'};
            }

            if($self->{'result'}->{'iscritical'} or $self->{'result'}->{'iswarning'}) {
                $message .= "\n".$self->{'out'};
                $message =~ s/^\-+$//mx;
            }
            if($self->{'config'}->{'reporttype'} eq 'nagios2') {
                $message =~ s/\n/<br>/mxg;
            }
            print $message.$perfdata."\n";

            $self->{'result'}->{'perfdata'} = $perfdata;
            return $rc;
        }

        #MRTG plugin compatibility
        elsif( $self->{'config'}->{'reporttype'} eq 'mrtg' )
        {    #report results in MRTG format
            if( $self->{'result'}->{'totalcasesfailedcount'} > 0 ) {
                print "$self->{'result'}->{'totalruntime'}\n$self->{'result'}->{'totalruntime'}\n\nWebInject CRITICAL - $self->{'result'}->{'returnmessage'} \n";
            }
            else {
                print "$self->{'result'}->{'totalruntime'}\n$self->{'result'}->{'totalruntime'}\n\nWebInject OK - All tests passed successfully in $self->{'result'}->{'totalruntime'} seconds \n";
            }
        }

        #External plugin. To use it, add something like that in the config file:
        # <reporttype>external:/home/webinject/Plugin.pm</reporttype>
        elsif ( $self->{'config'}->{'reporttype'} =~ /^external:(.*)/mx ) {
            our $webinject = $self; # set scope of $self to global, so it can be access in the external module
            unless( my $return = do $1 ) {
                croak "couldn't parse $1: $@\n" if $@;
                croak "couldn't do $1: $!\n" unless defined $return;
                croak "couldn't run $1\n" unless $return;
            }
        }

        else {
            $self->_usage("ERROR: only 'nagios', 'nagios2', 'mrtg', 'external', or 'standard' are supported reporttype values");
        }

    }

    return 1 if $self->{'result'}->{'totalcasesfailedcount'} > 0;
    return 0;
}

################################################################################
# delete any files leftover from previous run if they exist
sub _whackoldfiles {
    my $self = shift;

    for my $file (qw/plot.log plot.plt plot.png/) {
        unlink $self->{'config'}->{'output_dir'}.$file if -e $self->{'config'}->{'output_dir'}.$file;
    }

    # verify files are deleted, if not give the filesystem time to delete them before continuing
    while (-e $self->{'config'}->{'output_dir'}."plot.log"
        or -e $self->{'config'}->{'output_dir'}."plot.plt"
        or -e $self->{'config'}->{'output_dir'}."plot.png"
    ) {
        sleep .5;
    }
    return;
}

################################################################################
# call the external plotter to create a graph (if we are in the appropriate mode)
sub _plotit {
    my $self = shift;

    # do this unless: monitor is disabled in gui, or running standalone mode without config setting to turn on plotting
    if(   ( $self->{'gui'} and $self->{'monitorenabledchkbx'} ne 'monitor_off')
       or (!$self->{'gui'} and $self->{'config'}->{'standaloneplot'} eq 'on')
    ) {
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
                system $gnuplot, $self->{'config'}->{output_dir}."plot.plt";    # plot it
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
# fix a user supplied regex to make it compliant with mx options
sub _fix_regex {
    my $self  = shift;
    my $regex = shift;

    $regex =~ s/\\\ / /mx;
    $regex =~ s/\ /\\ /gmx;

    return $regex;
}

################################################################################
# command line options
sub _getoptions {
    my $self = shift;

    my( @sets, $opt_version, $opt_help, $opt_configfile );
    Getopt::Long::Configure('bundling');
    my $opt_rc = GetOptions(
        'h|help'          => \$opt_help,
        'v|V|version'     => \$opt_version,
        'c|config=s'      => \$opt_configfile,
        'o|output=s'      => \$self->{'config'}->{'output_dir'},
        'n|no-output'     => \$self->{'config'}->{'nooutput'},
        'r|report-type=s' => \$self->{'config'}->{'reporttype'},
        't|timeout=i'     => \$self->{'config'}->{'timeout'},
        's=s'             => \@sets,
    );
    if(!$opt_rc or $opt_help) {
        $self->_usage();
    }
    if($opt_version) {
        print "WebInject version $Webinject::VERSION\nFor more info: http://www.webinject.org\n";
        exit 3;
    }
    $self->_read_config_xml($opt_configfile);
    for my $set (@sets) {
        my ( $key, $val ) = split /=/mx, $set, 2;
        if($key eq 'httpauth') {
            $self->_set_http_auth($val);
        } else {
            $self->{'config'}->{ lc $key } = $val;
        }
    }
    return;
}

################################################################################
# _out -  print text to STDOUT and save it for later retrieval
sub _out {
    my $self = shift;
    my $text = shift;
    if($self->{'config'}->{'reporttype'} !~ /^nagios/mx and !$self->{'config'}->{'nooutput'}) {
        print $text;
    }
    $self->{'out'} .= $text;
    return;
}

################################################################################
# print usage
sub _usage {
    my $self = shift;
    my $text = shift;

    print $text."\n\n" if defined $text;

    print <<EOB;
    Usage:
      $0
                [-c|--config config_file]
                [-o|--output output_location]
                [-n|--no-output]
                [-t|--timeout]
                [-r|--report-type]
                [-s key=value]
                [testcase_file [XPath]]
      $0 --version|-v
EOB
    exit 3;
}

=head1 EXAMPLES

=head2 example test case

  <testcases>
    <case
      id             = "1"
      description1   = "Sample Test Case"
      method         = "get"
      url            = "{BASEURL}/test.jsp"
      verifypositive = "All tests succeded"
      warning        = "5"
      critical       = "15"
      label          = "testpage"
      errormessage   = "got error: {PARSERESPONSE}"
    />
  </testcases>

detailed description about the syntax of testcases can be found on the Webinject homepage.


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
