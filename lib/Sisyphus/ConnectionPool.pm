package Sisyphus::ConnectionPool;

use strict;

use Sisyphus::Connector;
use Data::Dumper;


=head1 NAME

Sisyphus::ConnectionPool - Maintain a pool of Sisyphus connections

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Sisyphus::ConnectionPool;

    my $foo = Sisyphus::ConnectionPool->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 FUNCTIONS

=head2 new

Contructor.

=cut

sub new {
	my $class = shift;
	my $self = {
		# data needed for pool maintenance
		connections_to_make => 1,
		freepool => [],

		# data needed for creation of connection instances
		host => '',
		port => 0,
		protocolName => undef,
		protocolArgs => undef,

		application => undef,
		response_handler => undef,
		on_error => \&onError,
		server_closed => \&serverClosed,
	};
	return(bless($self, $class));
}

=head2 connect

Connect pool of connections to server. Provide it a callback, to be
called once all connections are made.

=cut

sub connect {
	my $self = shift;
	my $cb = shift;

	foreach my $i (0 .. ($self->{connections_to_make} - 1)) {
		$self->{connections}->{$i}->{connection} = Sisyphus::Connector->new();
		$self->{connections}->{$i}->{connection}->{host} = $self->{host};
		$self->{connections}->{$i}->{connection}->{port} = $self->{port};
		$self->{connections}->{$i}->{connection}->{protocolName} = $self->{protocolName};
		$self->{connections}->{$i}->{connection}->{protocolArgs} = $self->{protocolArgs};
		#$self->{connections}->{$i}->{connection}->{application} = $self->{application};
		#$self->{connections}->{$i}->{connection}->{response_handler} = $self->{response_handler};
		$self->{connections}->{$i}->{connection}->{on_error} = $self->{on_error};
		$self->{connections}->{$i}->{connection}->{server_closed} = $self->{server_closed};

		$self->{connections}->{$i}->{state} = "disconnected";
		$self->{connections}->{$i}->{index} = $i;
		$self->{connections}->{$i}->{connection}->connect(sub { 
			print "connection $i made!\n";
			$self->{connections}->{$i}->{state} = "connected";
			push(@{$self->{freepool}}, $self->{connections}->{$i});
			if (scalar(@{$self->{freepool}}) == $self->{connections_to_make}) {
				print STDERR "all connections made!\n";
				$cb->();
			}
		});
	}
}

=head2 claim

Returns a free Connection instance (actually a hash that includes a
Connection instance, in its 'connection' key. Make sure you eventually
release it!

Will die when no free connections are left.

=cut

sub claim {
	my $self = shift;
	unless (scalar(@{$self->{freepool}})) {
		die "No free Connections";
	}

	my $c = pop(@{$self->{freepool}});

	$c->{state} = "claimed";

	print "Claimed Connection $c->{index}\n";

	return $c;
}

=head2 release

Returns a connection instance back to the pool of free instances.

No return value.

=cut

sub release {
	my ($self, $c) = @_;
	$c->{state} = "connected";
	push(@{$self->{freepool}}, $c);
	
	print "Released Connection $c->{index}\n";
	print "calling release_cb, if it exists.\n";

	my $rcb = $self->{release_cb};

	if ($rcb){
		$rcb->();
	}
}

=head2 send

Send data on an arbitrary free Connection instance. If you are entering
an interactive transaction, you probably want claim/release.

NOTE do *not* send data using this method if a potential side-effect of
you sending a message is a return message. It'll mess everything up.

Will die when no free connections exist.

=cut

sub send {
	my $self = shift;
	my $m = shift;
	die "No free Connections" unless scalar(@{$self->{freepool}});

	$self->{freepool}->[0]->send($m);
}

=head2 claimable
	
Returns true if we have a free connection that's claim()able.

=cut

sub claimable {
	my $self = shift;

	return scalar(@{$self->{freepool}});


}
