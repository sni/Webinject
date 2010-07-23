use inc::Module::Install;

name 'Webinject';
all_from 'lib/Webinject.pm';
license 'gpl2';

resources(
    'homepage',   => 'http://www.webinject.org',
    'bugtracker'  => 'http://github.com/sni/Webinject/issues',
    'repository', => 'http://github.com/sni/Webinject',
);

requires 'LWP'                     => 0;
requires 'XML::Simple'             => 0;
requires 'HTTP::Request::Common'   => 0;
requires 'HTTP::Cookies'           => 0;
requires 'Time::HiRes'             => 0;
requires 'Getopt::Long'            => 0;
requires 'Crypt::SSLeay'           => 0;
requires 'XML::Parser'             => 0;
requires 'Error'                   => 0;
requires 'File::Temp'              => 0;

auto_install;
WriteAll;
