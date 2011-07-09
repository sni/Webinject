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
        plan tests => 5;
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
test_case_config();


##################################################
# SUBs
##################################################

sub test_case_config {
    @ARGV = ($Bin."/data/20-full_test.xml");
    my $expected = {
          'addheader'           => 'Blah: Blurbs',
          'description1'        => 'description',
          'description2'        => 'description2',
          'errormessage'        => 'in case of errors display this',
          'id'                  => '1',
          'logrequest'          => 'yes',
          'logresponse'         => 'yes',
          'method'              => 'post',
          'parseresponse'       => 'Authorization:|\\n',
          'parseresponse1'      => 'HTTP|\\n',
          'parseresponse2'      => 'HTTP|\\n',
          'parseresponse3'      => 'HTTP|\\n',
          'parseresponse4'      => 'HTTP|\\n',
          'parseresponse5'      => 'HTTP|\\n',
          'postbody'            => 'a=1;b=2;c=3;c=4;test=postbodytestmessage;test2=teststring1',
          'posttype'            => 'application/x-www-form-urlencoded',
          'sleep'               => '1',
          'url'                 => 'http://localhost:58080/post',
          'verifynegative'      => 'this should be not visible',
          'verifynegative1'     => 'this should be not visible',
          'verifynegative2'     => 'this should be not visible',
          'verifynegative3'     => 'this should be not visible',
          'verifynegativenext'  => 'this test is also not available',
          'verifypositivenext'  => 'bad path:',
          'verifypositive'      => 'postbodytestmessage',
          'verifypositive2'     => 'teststring1',
          'verifypositive3'     => 'Client\-Response\-Num:\ 1',
          'verifyresponsecode'  => 200,
          'passedcount'         => 8,
          'failedcount'         => 0,
          'iswarning'           => 1,
          'iscritical'          => 0,
    };
    my $webinject = Webinject->new();
    $webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
    my $rc = $webinject->engine();
    is($rc, 1, '07-config_options.xml - return code') or diag(Dumper($webinject));
    my $firstcase = $webinject->{'result'}->{'files'}->[0]->{'cases'}->[0];
    delete $firstcase->{'messages'};
    delete $firstcase->{'latency'};
    delete $firstcase->{'response'};
    delete $firstcase->{'request'};
    is_deeply($firstcase, $expected, '20-full_test.xml - first expected case');

    my $expected2 =  {
          'description1'       => 'description',
          'failedcount'        => 0,
          'id'                 => '2',
          'method'             => 'get',
          'passedcount'        => 3,
          'url'                => 'http://localhost:58080/badpath',
          'verifyresponsecode' => 400,
          'iswarning'          => 0,
          'iscritical'         => 0,
        };
    my $secondcase = $webinject->{'result'}->{'files'}->[0]->{'cases'}->[1];
    delete $secondcase->{'messages'};
    delete $secondcase->{'latency'};
    delete $secondcase->{'response'};
    delete $secondcase->{'request'};
    is_deeply($secondcase, $expected2, '20-full_test.xml - second expected case');
}
