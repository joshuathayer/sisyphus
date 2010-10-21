use inc::Module::Install;

name         'Sisyphus';
author       'Joshua Thayer <joshuamilesthayer@gmail.com>';
perl_version '5.005';
all_from     'lib/Sisyphus.pm';

build_requires 'Test::More';
requires	   'AnyEvent'	=> '5.201';
requires	   'AnyEvent::AIO'	=> '1.1';

recommends     'Log::Syslog::Fast' => 0;

auto_install;
license		'perl';

WriteAll;

