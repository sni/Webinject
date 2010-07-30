#!/usr/bin/env perl

##################################################

package TestWebServer;

use strict;
use Test::More;
use Data::Dumper;
use FindBin qw($Bin);
use base qw(HTTP::Server::Simple::CGI);

my $webserverpid;

# Fire up test webserver
sub handle_request {
    my $self   = shift;
    my $cgi    = shift;
    my $path   = $cgi->path_info();
    my $method = $cgi->request_method();

    # GET Requests
    if($method eq 'GET' and $path =~ m|/code/(\d+)|) {
        print "HTTP/1.0 $1\r\n\r\nrequest for response code $1\r\n";
    }
    elsif($method eq 'GET' and $path =~ m|/teststring|) {
        print "HTTP/1.0 200 OK\r\n\r\nthis is just a teststring";
    }
    elsif($method eq 'GET' and $path =~ m|/sleep/(\d+)|) {
        sleep($1);
        print "HTTP/1.0 200 OK\r\n\r\nsleeped $1 seconds";
    }
    elsif($method eq 'GET' and $path =~ m|/auth|) {
        if(defined $ENV{'HTTP_AUTHORIZATION'} and $ENV{'HTTP_AUTHORIZATION'} eq 'Basic dXNlcjpwYXNz') {
            print "HTTP/1.0 200 OK\r\n\r\nauth successfull";
        }
        elsif(defined $ENV{'HTTP_AUTHORIZATION'}) {
            print "HTTP/1.0 403 Forbidden\r\n\r\nyou are not authorized";
        } else {
            print "HTTP/1.0 401 Authorization required\r\n";
            print "WWW-Authenticate: Basic realm=\"my_realm\"\r\n";
            print "\r\n";
            print "got auth request with the following cgi object:\n";
        }
        print Dumper($cgi);
        print Dumper(\%ENV);
    }

    # POST Requests
    elsif($method eq 'POST' and $path =~ m|/post|) {
        print "HTTP/1.0 200 OK\r\n\r\n";
        print "got post request with the following cgi object:\n";
        print Dumper($cgi);
    } else {
        print "HTTP/1.0 400 Bad Request\r\n\r\n";
        print "bad path: '$path'\r\n";
    }
}

sub start_webserver {
    # start the server on port 508080
    $webserverpid = TestWebServer->new(58080)->background();
    $SIG{INT} = sub{ kill 2, $webserverpid if defined $webserverpid; undef $webserverpid; exit 1; };
}

##################################################
# stop our test webserver
END {
    kill 2, $webserverpid if defined $webserverpid;
}

1;