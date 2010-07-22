package Webinject;

use 5.006;
use strict;
use warnings;
use Carp;

our $VERSION = '1.50';


=head1 NAME

Webinject - Perl Module for testing web services

=head1 SYNOPSIS

    use Webinject;

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

=cut

sub new {
    my $class = shift;
    my(%options) = @_;

    my $self = {
      "verbose"           => 0,       # enable verbose output
    };

    for my $opt_key (keys %options) {
        if(exists $self->{$opt_key}) {
            $self->{$opt_key} = $options{$opt_key};
        }
        else {
            croak("unknown option: $opt_key");
        }
    }

    bless $self, $class;

    return $self;
}


########################################

=head1 METHODS

=head1 SEE ALSO

For more information about webinject visit http://www.webinject.org/

=head1 AUTHOR

Corey Goldberg, E<lt>corey@goldb.orgE<gt>
Sven Nierlein, E<lt>nierlein@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Sven Nierlein
Copyright (C) 2004-2006 by Corey Goldberg

This library is free software; you can redistribute it under the GPL2 license.

=cut

__END__
