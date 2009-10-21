package Sisyphus::ConnectionPool;

use strict;

use Sisyphus::Connector;
use Data::Dumper;
use Sislog;

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
		freepool => {},
		connectingPool => {},
		disconnectedPool => {},

		# data needed for creation of connection instances
		host => '',
		port => 0,
		protocolName => undef,
		protocolArgs => undef,

		application => undef,
		response_handler => undef,
		on_error => \&onError,
		server_closed => \&serverClosed,

		log => Sislog->new({use_syslog=>1, facility=>"Sisyphus-ConnectionPool"}),
	};
	$self->{log}->open();
	$self->{log}->log("Sisyphus::ConnectionPool instantiation");
	return(bless($self, $class));
}

=head2 connect

Connect pool of connections to server. Provide it a callback, to be
called once all connections are made.

=cut

sub connect {
	my $self = shift;
	my $cb = shift;

	# create connection instances
	foreach my $i (0 .. ($self->{connections_to_make} - 1)) {
		$self->{log}->log("creating connection $i to $self->{host}:$self->{port}");
		my $c = $self->createConnection($i);
		$self->{log}->log("created connection >>".$c->{id}."<<");
		$self->{disconnectedPool}->{ $c->{id} } = $c;
	}

	# attempt to make connections
	$self->connectAll(sub {
		$cb->();
	});
}

sub connectAll {
	my $self = shift;
	my $cb = shift;

	my $count = scalar(keys(%{$self->{disconnectedPool}}));
	my $connectionsReturned = 0;

	unless ($count) {
		$self->{log}->log("no connections in notConnectedPool to connect to");
		$cb->();
	}

	foreach my $i (keys(%{$self->{disconnectedPool}})) {
		my $c = $self->{disconnectedPool}->{$i};

		$self->{connectingPool}->{ $c->{id} } = $c;
		delete $self->{disconnectedPool}->{ $c->{id} };

		$self->connectOne($c, sub { 
			my $c = shift; # this is the connection object

			$connectionsReturned++;

			if ($connectionsReturned == $count) {
				$self->{log}->log("i think i'm done with attempting connections.");
				$cb->();
			}
		});
	}
}

sub createConnection {
	my ($self, $id) = @_;

	my $c = Sisyphus::Connector->new();
	$c->{host} = $self->{host};
	$c->{port} = $self->{port};
	$c->{protocolName} = $self->{protocolName};
	$c->{protocolArgs} = $self->{protocolArgs};
	$c->{on_error} = $self->{on_error};
	$c->{server_closed} = $self->{server_closed};
	$c->{id} = $id;
	

	return $c;
}

sub connectOne {
	my ($self, $c, $cb) = @_;
	$c->connect( sub {
		my $c = shift;

		if ($c->{connected}) {
			$self->{log}->log("connection state connecting->connected");
			delete $self->{connectingPool}->{ $c->{id} };
			$self->{freepool}->{ $c->{id} } = $c;
		} else {
			$self->{log}->log("connection state connecting->disconnected");
			delete $self->{connectingPool}->{ $c->{id} };
			$self->{disconnectedpool}->{ $c->{id} } = $c;
		}

		$cb->($c);
	});
}

=head2 claim

Returns a free Connection instance (actually a hash that includes a
Connection instance, in its 'connection' key. Make sure you eventually
release it!

Will die when no free connections are left.

=cut

sub claim {
	my $self = shift;
	my $cb = shift;

	unless (scalar(keys(%{$self->{freepool}}))) {
		$self->{log}->log("no free connections!");
		$cb->(undef);
	}

	$self->{log}->log(scalar(keys(%{$self->{freepool}})) . " connections available");

	my @c = values(%{ $self->{freepool} });
	my $c = $c[0];

	delete $self->{freepool}->{ $c->{id} };
	$self->{log}->log(scalar(keys(%{$self->{freepool}})) . " connections available");

	$c->{state} = "claimed";

	$self->{log}->log(ref($c));
	$self->{log}->log(ref($c->{connection}));
	$self->{log}->log(ref($c->{protocol}));

	$cb->($c);
}

=head2 release

Returns a connection instance back to the pool of free instances.

No return value.

=cut

sub release {
	my ($self, $c) = @_;
	$c->{state} = "connected";
	$self->{freepool}->{ $c->{id} } = $c;
	
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

Will log an error when no free connections exist.

=cut

sub send {
	my $self = shift;
	my $m = shift;
	$self->{log}->log("No free Connections in send") unless scalar(keys(%{$self->{freepool}}));

	my $cid = keys(%{$self->{freepool}})->[0];

	$self->{freepool}->{ $cid }->send($m);
}

=head2 claimable
	
Returns true if we have a free connection that's claim()able.

=cut

sub claimable {
	my $self = shift;
	
	return scalar(keys(%{$self->{freepool}}));
}
