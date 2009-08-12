package Sisyphus::Application;

use strict;

sub new {
	my ($class, $name) = @_;

	my $self = {};

    bless($self, $class); 

	return $self;                 # $self is already blessed
}

sub message {

	print STDERR "application doesn't implement message() method\n";

}

sub new_connection {


	print STDERR "application doesn't implement new_connection() method\n";

}

1;
