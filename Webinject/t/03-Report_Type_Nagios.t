#!/usr/bin/env perl

##################################################

use strict;
use Test::More;
use Data::Dumper;
use FindBin qw($Bin);
use lib 't';


if($ENV{TEST_AUTHOR}) {
    eval "use HTTP::Server::Simple::CGI";
    if($@) {
        plan skip_all => 'HTTP::Server::Simple::CGI required';
    }
    else{
        plan tests => 6;
    }
}
else{
    plan skip_all => 'Author test. Set $ENV{TEST_AUTHOR} to a true value to run.';
}


use_ok('Webinject');

my $webinject = Webinject->new();
isa_ok($webinject, "Webinject", 'Object is a Webinject');

require TestWebServer;
TestWebServer->start_webserver();

##################################################
# start our test cases
test_case_01();
test_case_02();
test_case_03();
test_case_04();


##################################################
# SUBs
##################################################

##################################################
# Test File 01
sub test_case_01 {
    @ARGV = ('-r', 'nagios', $Bin."/data/01-response_codes.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    my $rc = $webinject->engine();
    is($rc, 2, '01-response_codes.xml - return code');
}

##################################################
# Test File 02
sub test_case_02 {
    @ARGV = ('-r', 'nagios', $Bin."/data/02-string_verification.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    my $rc = $webinject->engine();
    is($rc, 0, '02-string_verification - return code');
}

##################################################
# Test File 03
sub test_case_03 {
    @ARGV = ('-r', 'nagios', $Bin."/data/03-parse_response.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    my $rc = $webinject->engine();
    is($rc, 0, '03-parse_response.xml - return code');
}

##################################################
# Test File 04
sub test_case_04 {
    @ARGV = ('-r', 'nagios', $Bin."/data/04-repeated_tests.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    my $rc = $webinject->engine();
    is($rc, 2, '04-repeated_tests.xml - return code');
}
