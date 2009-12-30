package Sisyphus::Proto::Trivial;

use strict;
use Scalar::Util qw/ weaken /;
#use Devel::Cycle;

# a trivial protocol for integration with an AnyEvent-based server

use constant HEADER_STATE => 0;
use constant PAYLOAD_STATE => 1;
use constant VERSION => 0;

use constant HEADER_LEN => 5;

sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my $self = {
	};
	bless $self, $class;
}

# client side.
# will get called at connect-time.
sub on_connect {
	my ($self, $cb) = @_;

	$self->{connected} = 1;

	# once we're authenticated and ready to use, call this...
	$self->{cb} = $cb;

	# set up a reader, so the server can tell us things
	$self->receive_message_length();

	# ok we call our App's callback, if there is one
	$self->{cb}->();
}

# server side.
sub on_client_connect {
	my $self = shift;

	$self->receive_message_length();
}

sub on_client_disconnect {
	# do nothing (yet?)
}

# ######### both ####
sub receive_message_length {
	my $self = shift;

	weaken $self;

	my $handle = $self->{handle};

	$handle->push_read(
		chunk => HEADER_LEN,
		sub {
			my ($handle, $data) = @_;
			# we have 5 bytes of triv-proto header
			# 8 bits of version, 32 bits of packet length
			my ($v, $len) = unpack("CV", $data);
			$self->receive_message($len);
		}
	);
}

# message over the wire from peer.
# this could be server or client
sub receive_message {
	my $self = shift;

	weaken $self;

	my $len = shift;
	my $handle = $self->{handle};
	$handle->push_read(
		chunk => $len,
		sub {
			my ($handle, $data) = @_;
			# ok, $data is actual message data now
			$self->{app_callback}->($data);
			$self->receive_message_length();
		},
	);
}

sub frame {
	my ($self, $scalar) = @_;

        # Devel::Cycle::find_cycle($self);
	
	my $len = length($scalar);

	$self->{handle}->push_write( pack("CV", VERSION, $len) );
	$self->{handle}->push_write( $scalar );
}

1;
