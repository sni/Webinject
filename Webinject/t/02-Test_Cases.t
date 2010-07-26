#!/usr/bin/env perl

##################################################

use strict;
use Test::More;
use Data::Dumper;
use FindBin qw($Bin);


if($ENV{TEST_AUTHOR}) {
    eval "use HTTP::Server::Simple::CGI";
    if($@) {
        plan skip_all => 'HTTP::Server::Simple::CGI required';
    }
    else{
        plan tests => 18;
    }
}
else{
    plan skip_all => 'Author test. Set $ENV{TEST_AUTHOR} to a true value to run.';
}


use_ok('Webinject');

my $webinject = Webinject->new();
isa_ok($webinject, "Webinject", 'Object is a Webinject');


# start the server on port 508080
my $webserverpid = TestWebServer->new(58080)->background();
$SIG{INT} = sub{ kill 2, $webserverpid if defined $webserverpid; undef $webserverpid; exit 1; };
sleep(1);

##################################################
# start our test cases
test_case_01();
test_case_02();
test_case_03();
test_case_04();
test_case_05();



##################################################
# SUBs
##################################################

##################################################
# Test File 01
sub test_case_01 {
    @ARGV = ($Bin."/data/01-response_codes.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    $webinject->engine();
    is($webinject->{'passedcount'}, 1, '01-response_codes.xml - passed count');
    is($webinject->{'failedcount'}, 1, '01-response_codes.xml - fail count');
}

##################################################
# Test File 02
sub test_case_02 {
    @ARGV = ($Bin."/data/02-string_verification.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    $webinject->engine();
    is($webinject->{'passedcount'}, 9, '02-string_verification.xml - passed count');
    is($webinject->{'failedcount'}, 0, '02-string_verification.xml - fail count');
}

##################################################
# Test File 03
sub test_case_03 {
    @ARGV = ($Bin."/data/03-parse_response.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    $webinject->engine();
    is($webinject->{'passedcount'}, 3, '03-parse_response.xml - passed count');
    is($webinject->{'failedcount'}, 0, '03-parse_response.xml - fail count');
}

##################################################
# Test File 04
sub test_case_04 {
    @ARGV = ($Bin."/data/04-repeated_tests.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    $webinject->engine();
    is($webinject->{'passedcount'}, 5, '04-repeated_tests.xml - passed count');
    is($webinject->{'failedcount'}, 5, '04-repeated_tests.xml - fail count');
}



##################################################
# Reporttypes
sub test_case_05 {
    for my $type (qw/standard nagios mrtg external:t\/data\/external.pm/) {
        @ARGV = (
                 "-r", $type,
                 $Bin."/data/05-report_types.xml"
                );
        my $webinject = Webinject->new();
        $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
        $webinject->engine();
        is($webinject->{'passedcount'}, 1, 'reporttype: '.$type.' 05-report_types.xml - passed count');
        is($webinject->{'failedcount'}, 1, 'reporttype: '.$type.' 05-report_types.xml - fail count');
    }
}

##################################################
# Fire up test webserver
{
    package TestWebServer;
    use base qw(HTTP::Server::Simple::CGI);

    sub handle_request {
        my $self   = shift;
        my $cgi    = shift;
        my $path   = $cgi->path_info();
        my $method = $cgi->request_method();
        if($method eq 'GET' and $path =~ m|/code/(\d+)|) {
            print "HTTP/1.0 $1\r\n\r\nrequest for response code $1\r\n";
        }
        elsif($method eq 'GET' and $path =~ m|/teststring|) {
            print "HTTP/1.0 200 OK\r\n\r\nthis is just a teststring";
        } else {
            print "HTTP/1.0 400 Bad Request\r\n\r\n";
            print "bad path: '$path'\r\n";
        }
    }
}

##################################################
# stop our test webserver
kill 2, $webserverpid if defined $webserverpid;
END {
    kill 2, $webserverpid if defined $webserverpid;
}
