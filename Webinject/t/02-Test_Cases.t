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
        plan tests => 8;
    }
}
else{
    plan skip_all => 'Author test. Set $ENV{TEST_AUTHOR} to a true value to run.';
}


use_ok('Webinject');

my $webinject = Webinject->new();
isa_ok($webinject, "Webinject", 'Object is a Webinject');

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

# start the server on port 508080
my $webserverpid = TestWebServer->new(58080)->background();
$SIG{INT} = sub{ kill 2, $webserverpid if defined $webserverpid; undef $webserverpid; exit 1; };
sleep(1);

##################################################
# Test File 01
$webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
@ARGV = ($Bin."/data/01-response_codes.xml");
$webinject->engine();
is($webinject->{'passedcount'}, 1, '01-response_codes.xml - passed count');
is($webinject->{'failedcount'}, 1, '01-response_codes.xml - fail count');

##################################################
# Test File 02
$webinject = Webinject->new();
$webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
@ARGV = ($Bin."/data/02-string_verification.xml");
$webinject->engine();
is($webinject->{'passedcount'}, 9, '02-string_verification.xml - passed count');
is($webinject->{'failedcount'}, 0, '02-string_verification.xml - fail count');

##################################################
# Test File 04
$webinject = Webinject->new();
$webinject->{'config'}->{'baseurl'} = 'http://localhost:58080';
@ARGV = ($Bin."/data/03-parse_response.xml");
$webinject->engine();
is($webinject->{'passedcount'}, 3, '03-parse_response.xml - passed count');
is($webinject->{'failedcount'}, 0, '03-parse_response.xml - fail count');



##################################################
# stop our test webserver
kill 2, $webserverpid if defined $webserverpid;
END {
    kill 2, $webserverpid if defined $webserverpid;
}
