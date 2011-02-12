#!/usr/bin/env perl

##################################################

use strict;
use Test::More;
use Data::Dumper;
use FindBin qw($Bin);
use lib 't';


if(!$ENV{TEST_AUTHOR}) {
    plan skip_all => 'Author test. Set $ENV{TEST_AUTHOR} to a true value to run.';
}
elsif(!$ENV{'TEST_PROXY'}) {
    plan skip_all => 'Author test. Set $ENV{TEST_PROXY} to run this test.';
}
else{
    plan tests => 8;
}


use_ok('Webinject');

my $webinject = Webinject->new();
isa_ok($webinject, "Webinject", 'Object is a Webinject');

for my $key (qw/http_proxy https_proxy HTTP_PROXY HTTPS_PROXY/) {
    delete($ENV{$key});
}

##################################################
# start our test cases
my $webinject = Webinject->new("proxy" => $ENV{'TEST_PROXY'});
test_case($webinject, 'http://www.google.de');
test_case($webinject, 'https://encrypted.google.com/');

##################################################
# SUBs
##################################################

##################################################
# Test Case
sub test_case {
    my $webinject = shift;
    my $url       = shift;
    my $case = {
        'logresponse'         => 'yes',
        'logrequest'          => 'yes',
        'verifyresponsecode'  => 200,
        'verifypositive'      => 'Google',
        'url'                 => $url,
    };
    my $expected = {
        'id'                  => 1,
        'passedcount'         => 2,
        'failedcount'         => 0,
        'url'                 => $case->{'url'},
        'logresponse'         => 'yes',
        'logrequest'          => 'yes',
        'verifyresponsecode'  => 200,
        'verifypositive'      => $case->{'verifypositive'},

    };
    my $result = $webinject->_run_test_case($case);

    delete $result->{'messages'};
    delete $result->{'latency'};
    delete $result->{'response'};
    delete $result->{'request'};
    is_deeply($result, $expected, '01 - proxy '.$url.' - result') or BAIL_OUT("expected: \n".Dumper($expected)."\nresult: \n".Dumper($result));
    is($webinject->{'result'}->{'iscritical'}, 0, '06 - proxy '.$url.' - iscritical');
    is($webinject->{'result'}->{'iswarning'}, 0, '06 - proxy '.$url.' - iswarning');
}
