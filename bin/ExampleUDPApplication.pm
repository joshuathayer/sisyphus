package ExampleUDPApplication;

use strict;
use Data::Dumper;

# implements a trivial little application
my @responses;
my $request_count = 0;

sub new {
	my $class = shift;
	my $self = { };
	return(bless($self, $class));
}

sub message {
	my ($self, $host, $port, $message, $stash) = @_;

	$request_count += 1;

	print "example UDP application got the following message(s) from host $host:$port:\n";
	print Dumper $message;

}

1;
