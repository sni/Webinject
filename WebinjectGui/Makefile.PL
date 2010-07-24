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
