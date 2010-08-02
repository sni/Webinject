use inc::Module::Install;

name 'Webinject-Gui';
all_from 'lib/Webinject/Gui.pm';
license 'gpl2';

resources(
    'homepage',   => 'http://www.webinject.org',
    'bugtracker'  => 'http://github.com/sni/Webinject/issues',
    'repository', => 'http://github.com/sni/Webinject',
);

requires 'Webinject'             => '1.50';
requires 'Tk'                    => 0;
requires 'Tk::Stderr'            => 0;
requires 'Tk::ROText'            => 0;
requires 'Tk::Compound'          => 0;
requires 'Tk::ProgressBar::Mac'  => 0;
requires 'Tk::NoteBook'          => 0;
requires 'Tk::PNG'               => 0;

auto_install;
WriteAll;

open(my $fh, '>>', 'Makefile') or die('cannot write to Makefile');
print $fh <<EOT;
webinjectgui.pl ::
	echo '#!/usr/bin/env perl'  > ./webinjectgui.pl
	echo '# nagios: +epn'      >> ./webinjectgui.pl
	echo ''                    >> ./webinjectgui.pl
	cat ../Webinject/lib/Webinject.pm lib/Webinject/Gui.pm ./bin/webinjectgui.pl | grep -v '^use Webinject' | grep -v '__END__' >> ./webinjectgui.pl
	chmod 755 ./webinjectgui.pl
EOT
close($fh);
