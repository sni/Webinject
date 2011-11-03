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
        plan tests => 44;
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
test_case_05();
test_case_06();
test_case_07();
test_case_08();
test_case_09();



##################################################
# SUBs
##################################################

##################################################
# Test File 01
sub test_case_01 {
    @ARGV = ($Bin."/data/01-response_codes.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    my $rc = $webinject->engine();
    is($webinject->{'result'}->{'totalpassedcount'}, 1, '01-response_codes.xml - passed count');
    is($webinject->{'result'}->{'totalfailedcount'}, 1, '01-response_codes.xml - fail count');
    is($rc, 1, '01-response_codes.xml - return code');
}

##################################################
# Test File 02
sub test_case_02 {
    @ARGV = ($Bin."/data/02-string_verification.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    my $rc = $webinject->engine();
    is($webinject->{'result'}->{'totalpassedcount'}, 9, '02-string_verification.xml - passed count');
    is($webinject->{'result'}->{'totalfailedcount'}, 0, '02-string_verification.xml - fail count');
    is($rc, 0, '02-string_verification - return code');
}

##################################################
# Test File 03
sub test_case_03 {
    @ARGV = ($Bin."/data/03-parse_response.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    my $rc = $webinject->engine();
    is($webinject->{'result'}->{'totalpassedcount'}, 3, '03-parse_response.xml - passed count');
    is($webinject->{'result'}->{'totalfailedcount'}, 0, '03-parse_response.xml - fail count');
    is($rc, 0, '03-parse_response.xml - return code');
}

##################################################
# Test File 04
sub test_case_04 {
    @ARGV = ($Bin."/data/04-repeated_tests.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    my $rc = $webinject->engine();
    is($webinject->{'result'}->{'totalpassedcount'}, 5, '04-repeated_tests.xml - passed count');
    is($webinject->{'result'}->{'totalfailedcount'}, 5, '04-repeated_tests.xml - fail count');
    is($rc, 1, '04-repeated_tests.xml - return code');
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
        my $rc = $webinject->engine();
        is($webinject->{'result'}->{'totalpassedcount'}, 1, 'reporttype: '.$type.' 05-report_types.xml - passed count');
        is($webinject->{'result'}->{'totalfailedcount'}, 1, 'reporttype: '.$type.' 05-report_types.xml - fail count');
        is($rc, 1, '05-report_types.xml - return code') if $type ne 'nagios';
        is($rc, 2, '05-report_types.xml - return code') if $type eq 'nagios';
    }
}

##################################################
# Test File 06
sub test_case_06 {
    @ARGV = ('-r', 'nagios', $Bin."/data/06-thresholds.xml", "testcases/case[1]");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    my $rc = $webinject->engine();
    is($webinject->{'result'}->{'totalpassedcount'}, 3, '06-thresholds.xml [1] - passed count');
    is($webinject->{'result'}->{'totalfailedcount'}, 0, '06-thresholds.xml [1] - fail count');
    is($rc, 0, '06-thresholds.xml [1] - return code');

    @ARGV = ('-r', 'nagios', $Bin."/data/06-thresholds.xml", "testcases/case[2]");
    $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    $rc = $webinject->engine();
    is($webinject->{'result'}->{'totalpassedcount'}, 2, '06-thresholds.xml [2] - passed count');
    is($webinject->{'result'}->{'totalfailedcount'}, 1, '06-thresholds.xml [2] - fail count');
    is($rc, 1, '06-thresholds.xml [2] - return code');

    @ARGV = ('-r', 'nagios', $Bin."/data/06-thresholds.xml", "testcases/case[3]");
    $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    $rc = $webinject->engine();
    is($webinject->{'result'}->{'totalpassedcount'}, 1, '06-thresholds.xml [3] - passed count');
    is($webinject->{'result'}->{'totalfailedcount'}, 2, '06-thresholds.xml [3] - fail count');
    is($rc, 2, '06-thresholds.xml [3] - return code');
}

##################################################
# Test Case 7 / File 01
sub test_case_07 {
    @ARGV = ("-s", "baseurl=http://localhost:58080", $Bin."/data/01-response_codes.xml");
    my $webinject = Webinject->new();
    my $rc = $webinject->engine();
    is($webinject->{'result'}->{'totalpassedcount'}, 1, '01-response_codes.xml - passed count');
    is($webinject->{'result'}->{'totalfailedcount'}, 1, '01-response_codes.xml - fail count');
    is($rc, 1, '01-response_codes.xml - return code');
}


##################################################
# Test Case 8 / File 08
sub test_case_08 {
    @ARGV = ("-s", "baseurl=http://localhost:58080", "-s", "code1=200", "-s", "code_500=500", "-s", "method=get", $Bin."/data/08-custom_var.xml");
    my $webinject = Webinject->new();
    my $rc = $webinject->engine();
    is($webinject->{'result'}->{'totalpassedcount'}, 1, '08-custom_var.xml - passed count');
    is($webinject->{'result'}->{'totalfailedcount'}, 1, '08-custom_var.xml - fail count');
    is($rc, 1, '01-response_codes.xml - return code');
}


##################################################
# Test Case 9 / File 09
sub test_case_09 {
    @ARGV = ($Bin."/data/09-fileupload.xml");
    my $webinject = Webinject->new();
    my $rc = $webinject->engine();
    is($webinject->{'result'}->{'totalpassedcount'}, 4, '09-fileupload.xml - passed count');
    is($webinject->{'result'}->{'totalfailedcount'}, 0, '09-fileupload.xml - fail count');
    is($rc, 0, '09-fileupload.xml - return code');
}

