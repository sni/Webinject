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

open(my $fh, '>>', 'Makefile') or die('cannot write to Makefile');
print $fh <<EOT;
check_webinject ::
	echo '#!/usr/bin/env perl'  > ./check_webinject
	echo '# nagios: +epn'      >> ./check_webinject
	echo ''                    >> ./check_webinject
	cat ./lib/Webinject.pm ./bin/webinject.pl | grep -v '^use Webinject' | grep -v '__END__' | sed -e 's/my \$\$webinject = Webinject->new\(\);/my \$\$webinject = Webinject->new(reporttype => \\"nagios\\", timeout => 30, break_on_errors => 1);/' >> ./check_webinject
	chmod 755 ./check_webinject

webinject.pl ::
	echo '#!/usr/bin/env perl'  > ./webinject.pl
	echo '# nagios: +epn'      >> ./webinject.pl
	echo ''                    >> ./webinject.pl
	cat ./lib/Webinject.pm ./bin/webinject.pl | grep -v '^use Webinject' | grep -v '__END__' >> ./webinject.pl
	chmod 755 ./webinject.pl
EOT
close($fh);
