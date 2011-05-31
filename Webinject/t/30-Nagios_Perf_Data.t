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


##################################################
# SUBs
##################################################

##################################################
# Test File 01
sub test_case_01 {
    @ARGV = ('-r', 'nagios', $Bin."/data/30-nagios_perf_data.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    my $rc = $webinject->engine();
    is($rc, 2, '30-nagios_perf_data.xml - return code');
    like($webinject->{'result'}->{'perfdata'}, '/time=([\d\.]+);0;0;0;0 case1=([\d\.]+);0;0;0;0 case2=([\d\.]+);0;0;0;0 testlabel=([\d\.]+);0;0;0;0 case4=([\d\.]+);0;0;0;0/', 'performance data');
}

##################################################
# Test File 02
sub test_case_02 {
    @ARGV = ('-r', 'nagios', '-s', 'break_on_errors=1', $Bin."/data/30-nagios_perf_data.xml");
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    my $rc = $webinject->engine();
    is($rc, 2, '30-nagios_perf_data.xml - return code');
    like($webinject->{'result'}->{'perfdata'}, '/time=([\d\.]+);0;0;0;0 case1=([\d\.]+);0;0;0;0 case2=0;0;0;0;0 case3=0;0;0;0;0 case4=0;0;0;0;0/', 'performance data');
}
