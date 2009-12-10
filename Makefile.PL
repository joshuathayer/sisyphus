use inc::Module::Install;

name     'Sisyphus';
author   'Joshua Thayer <joshuamilesthayer@gmail.com>';
#perl_version 5.whatever;
all_from 'lib/Sisyphus.pm';

build_requires 'Test::More';
requires	'EV'		=> '3.8';
requires	'AnyEvent'	=> '5.201';
requires	'MySQL::Packet'	=> 0;
#requires	'AnyEvent::HTTP' => '1.43';
requires	'AnyEvent::HTTPD' => '0.82';
requires	'common::sense'	=> '1.0';
requires	'Object::Event'	=> '1.101';
requires	'IO::AIO'	=> '3.3';
requires	'AnyEvent::AIO'	=> '1.1';
requires	'URI'		=> '1.40';
requires	'Data::Hexdumper' => 0;
requires	'Log::Syslog::Fast' => 0;

auto_install;
license		'perl';

WriteAll;

