package ExampleApplication;

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

sub new_connection {
	my $self = shift;
	my @rest = @_;
}

sub remote_closed {
	my ($self, $host, $port, $fh) = @_;
}

sub message {
	my ($self, $host, $port, $message, $fh) = @_;

	# we return this filehandle- this will indicate to Sisyphus that we have
	# something to send back to the client. in this example case, we'll just
	# return a simple message

	$request_count += 1;
	print "got message $message->[0]\n";
	
	push(@responses, "hello request number $request_count");
	$self->{client_callback}->([$fh]);	
}

sub get_data {
	my ($self, $fh) = shift;

	return(pop(@responses));
}

1;
