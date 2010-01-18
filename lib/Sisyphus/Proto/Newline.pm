package Sisyphus::Proto::Newline;

use strict;
use Scalar::Util qw/ weaken /;
use Data::Dumper;
#use Devel::Cycle;

# this is a UDP protocol

# A simple protocol where messages are delimited by a blank line.
# I'm implementing this only for compatability with an existing app 

sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my $self = {
	};
	bless $self, $class;
}

sub datagram {
	my ($self, $d, $host, $port) = @_;

	unless ($d =~ /.*\r\n\r\n$/) {
		print STDERR "Proto::Newline got a malformed message from $host:$port\n";
		return;
	}

	my @commands;
	
	foreach my $m (split("\r\n\r\n", $d)) {
		my ($cmd, @res) = split("\r\n", $m);
		push(@commands, { command=>$cmd, args=>\@res });
	}

	print "command and args:\n";
	print Dumper \@commands;

	# we're modelling UDP lister after TCP listener.
	# we pass this back to our listener, which will pass it basically
	# untouched to our application. thus, this is the API definition
	# that Application implementors should use until it's documented
	$self->{app_callback}->(
		$host,
		$port,
		\@commands,
	);
}

sub frame {
	my ($self, $scalar) = @_;

        # Devel::Cycle::find_cycle($self);
	
	my $len = length($scalar);

	$self->{handle}->push_write( $scalar );
}

1;
