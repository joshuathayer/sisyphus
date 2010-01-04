package Sisyphus::Proto::JSON;

use strict;
use Scalar::Util qw/ weaken /;
use JSON;
use Data::Dumper;

# a very simple JSON-based network 'protocol'. messages are sent as JSON strings. 
# this modules is really trivial, since anyevent already implements most of this itself

sub new {
	my $this = shift;
	my $class = ref($this) || $this;

	my $self = {
	};

	bless $self, $class;
}

# client side.
sub on_connect {
	my ($self, $cb) = @_;

	$self->{connected} = 1;

	# we use this callback to indicate to our app that we're ready to send something
	$self->{cb} = $cb;

	# set up handler for reading messages from server
	$self->setup_read();

	# ...and, we're ready to send now
	$self->{cb}->();
}

# server side.
sub on_client_connect {
	my ($self) = @_;

	# set up handle for reading messages from client
	$self->setup_read();
}

# receives a json message from underlying AnyEvent handle, dispatches the object
# to our application, goes back for more reads
sub setup_read {
	my ($self) = @_;

	$self->{handle}->push_read(json=>sub {
		my ($handle, $obj) = @_;
		$self->{app_callback}->($obj);
		$self->setup_read();
	});
}

sub on_client_disconnect {
	my ($self) = @_;

	$self->{connected} = 0;
}

sub frame {
	my ($self, $obj) = @_;

	$self->{handle}->push_write(json => $obj);
	#$self->{handle}->push_write(\012);
}

1;
