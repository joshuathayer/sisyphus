package TestApplication;

use strict;

# implements a trivial little application

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
	
	$self->{client_callback}->([$fh]);	
}

sub get_data {
	my ($self, $fh) = shift;

	return("test application");
}

1;
