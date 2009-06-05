#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'Sisyphus' );
}

diag( "Testing Sisyphus $Sisyphus::VERSION, Perl $], $^X" );
