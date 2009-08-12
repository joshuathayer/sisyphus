package Sisyphus::Proto::Factory;

use strict; use warnings;

sub instantiate {
	my $class          = shift;
	my $requested_type = shift;
	my $args           = shift;

	my $location       = "Sisyphus/Proto/$requested_type.pm";
	my $klass          = "Sisyphus::Proto::$requested_type";

	require $location;

	return $klass->new($args);
}

1;
