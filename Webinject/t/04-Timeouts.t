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
        plan tests => 10;
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



##################################################
# SUBs
##################################################

##################################################
# Test File 01
sub test_case_01 {
    my $webinject = Webinject->new();
    my $case = {
        'url' => 'http://localhost:58080/sleep/2',
    };
    my $expected = {
        'id'          => 1,
        'passedcount' => 1,
        'failedcount' => 0,
        'url'         => 'http://localhost:58080/sleep/2',
    };
    my $result = $webinject->_run_test_case($case);
    is($result->{'latency'} > 2, 1, 'timeouts - latency');
    delete $result->{'messages'};
    delete $result->{'latency'};
    is_deeply($result, $expected, 'timeouts - result') or BAIL_OUT("expected: \n".Dumper($expected)."\nresult: \n".Dumper($result));
    is($webinject->{'result'}->{'iscritical'}, 0, 'timeouts - iscritical');
    is($webinject->{'result'}->{'iswarning'}, 0, 'timeouts - iswarning');
}

##################################################
# Test File 02
sub test_case_02 {
    my $webinject = Webinject->new();
    my $case = {
        'url' => 'http://localhost:58080/sleep/2',
        'warning'     => 1,
    };
    my $expected = {
        'id'          => 1,
        'passedcount' => 1,
        'failedcount' => 1,
        'url'         => 'http://localhost:58080/sleep/2',
        'warning'     => 1,
    };
    my $result = $webinject->_run_test_case($case);
    is($result->{'latency'} > 2, 1, 'timeouts - latency');
    delete $result->{'messages'};
    delete $result->{'latency'};
    is_deeply($result, $expected, 'timeouts - result') or BAIL_OUT("expected: \n".Dumper($expected)."\nresult: \n".Dumper($result));
    is($webinject->{'result'}->{'iscritical'}, 0, 'timeouts - iscritical');
    is($webinject->{'result'}->{'iswarning'}, 1, 'timeouts - iswarning');
}
