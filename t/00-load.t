#!perl -T

use Test::More tests => 2;

BEGIN {
	use_ok( 'Sisyphus' );
	use_ok( 'Sislog' );
}

diag( "Testing Sisyphus $Sisyphus::VERSION, Perl $], $^X" );
