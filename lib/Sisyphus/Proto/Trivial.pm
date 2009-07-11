package Sisyphus::Proto::Trivial;

use strict;

# a trivial protocol for integration with an AnyEvent-based server

use constant HEADER_STATE => 0;
use constant PAYLOAD_STATE => 1;
use constant VERSION => 0;

use constant HEADER_LEN => 5;

sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my $self = {
		bytes_wanted => HEADER_LEN,
		message_len => HEADER_LEN,
		buffer => '',
		state => HEADER_STATE,
	};
	bless $self, $class;
}

sub consume {
	my $self = shift;
	if ($self->{state} == HEADER_STATE) {
		#print "have " . length($self->{buffer}) . ", need " . $self->{message_len} . "!\n";
		if (length($self->{buffer}) == $self->{message_len}) {
			# we have 5 bytes of triv-proto header
			# 8 bits of version, 32 bits of packet length
			my ($v, $len) = unpack("CV", $self->{buffer});
			#print "want a message of len $len!\n";
			$self->{bytes_wanted} = $len;
			$self->{message_len} = $len;
			$self->{buffer} = '';
			$self->{state} = PAYLOAD_STATE;
			return undef;
		} else {
			#print "HEADER UNDERRUN!! buffer length " . length($self->{buffer}) . ", but i need " . $self->{message_len} . "!\n";
			$self->{bytes_wanted} = $self->{message_len} - length($self->{buffer});
			#print "meaning i need $self->{bytes_wanted} more bytes!\n";
			return undef;
		}
	} elsif ($self->{state} == PAYLOAD_STATE) {
		if (length($self->{buffer}) == $self->{message_len}) {
			my $message = $self->{buffer};
			$self->{buffer} = '';
			$self->{state} = HEADER_STATE;
			$self->{bytes_wanted} = HEADER_LEN;
			$self->{message_len} = HEADER_LEN;
			return ($message);
		} else {
			#print "buffer length " . length($self->{buffer}) . ", but i need " . $self->{message_len} . "!\n";
			$self->{bytes_wanted} = $self->{message_len} - length($self->{buffer});
			#print "meaning i need $self->{bytes_wanted} more bytes!\n";
			return undef;
		}
	}
}

sub frame {
	my $self = shift;
	my $scalar = shift;
	
	my $len = length($scalar);
	#print "frame length $len\n";

	return pack("CV", VERSION, $len) . $scalar;
}

1;
