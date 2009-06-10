package ExampleApplication;

use strict;

# implements a trivial little application

sub new {
	my $class = shift;
	my $self = { };
	return(bless($self, $class));
}

sub remote_closed {
	my ($self, $host, $port, $fh) = @_;
	
	print  "$host closed connection!\n";
}

sub message {
	my ($self, $host, $port, $message, $fh) = @_;

	print "received a message from host $host port $port:\n$message\n\n";

	# we return this filehandle- this will indicate to Sisyphus that we have
	# something to send back to the client. in this example case, we'll just
	# return a simple message
	return ([$fh]);
}

sub get_data {
	my ($self, $fh) = shift;

	return("hello from a trivial server app");
}

1;
