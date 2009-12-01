#!perl -T

use Test::More tests => 4;
use Sisyphus;

BEGIN {
	use_ok( 'Sisyphus::Proto::HTTP');
	use_ok( 'Sisyphus::Proto::Mysql');
	use_ok( 'Sisyphus::Proto::Trivial');
	use_ok( 'Sisyphus::Proto::FastCGI');
}

