use inc::Module::Install;

name     'Sisyphus';
all_from 'lib/Sisyphus.pm';
author   'Joshua Thayer <joshuamilesthayer@gmail.com>';

build_requires 'Test::More';

auto_install;

WriteAll;

