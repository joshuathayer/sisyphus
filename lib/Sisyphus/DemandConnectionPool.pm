package Sisyphus::DemandConnectionPool;

use strict;

use Sisyphus::Connector;
use Data::Dumper;
use Sislog;
use Scalar::Util qw/ weaken /;

=head1 NAME

Sisyphus::DemandConnectionPool - Maintain a pool of Sisyphus connections.  
Only create actual connections on demand. Support reconnection after idle
timeout.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Sisyphus::DemandConnectionPool;

    my $foo = Sisyphus::DemandConnectionPool->new();
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

		log => Sislog->new({use_syslog=>1, facility=>"Sisyphus-DemandConnectionPool"}),

        disconnect_after => 5,
	};
	$self->{log}->open();
	$self->{log}->log("Sisyphus::DemandConnectionPool instantiation");
	return(bless($self, $class));
}

=head2 connect

Connect pool of connections to server. Provide it a callback, to be
called once all connections are made.

=cut

sub connect {
	my ($self, $cb) = @_;

	weaken $self;

	# create connection instances
	foreach my $i (0 .. ($self->{connections_to_make} - 1)) {
		$self->{log}->log("creating connection $i to $self->{host}:$self->{port}");
		my $c = $self->createConnection($i);
		$self->{log}->log("created connection >>".$c->{id}."<<");
		$self->{disconnectedPool}->{ $c->{id} } = $c;
	}

    $cb->();
}

# not used
sub connectAll {
	my ($self, $cb) = @_;

	weaken $self;

	my $count = scalar(keys(%{$self->{disconnectedPool}}));
	my $connectionsReturned = 0;

	unless ($count) {
		$self->{log}->log("no connections in disconnectedPool to connect");
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
			}
			$cb->();
		});
	}
}

sub createConnection {
	my ($self, $id) = @_;

	weaken $self;

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

	weaken $self;

	$c->connect( sub {
		my $c = shift;

		if ($c->{connected}) {
			$self->{log}->log("connection state connecting->connected");
			delete $self->{connectingPool}->{ $c->{id} };
			$self->{freepool}->{ $c->{id} } = $c;
		} else {
			$self->{log}->log("connection state connecting->disconnected");
			delete $self->{connectingPool}->{ $c->{id} };
			$self->{disconnectedPool}->{ $c->{id} } = $c;
		}

		$cb->($c);
	});
}

=head2 claim

Returns a free Connection instance (actually a hash that includes a
Connection instance, in its 'connection' key. Make sure you eventually
release it!

Will cb->(undef) if there are no connections available immediately and no
connetions able to connect.

=cut

sub claim {
	my $self = shift;
	my $cb = shift;

    $self->{log}->log("in claim");

	if (not (scalar(keys(%{$self->{freepool}})))) {
        $self->{log}->log("nothing in freepool");
        if (scalar(keys(%{$self->{disconnectedPool}}))) {
            # ok so, we can start one connecting, and claim it
            # as soon as it's connected...
		    $self->{log}->log("nothing in freepool, but available disconnected");

            # grab a connection from the disconnected pool,
            # put it in the connecting pool
            my @k = keys(%{$self->{disconnectedPool}});
		    my $c = $self->{disconnectedPool}->{$k[0]};
		    $self->{connectingPool}->{ $c->{id} } = $c;
		    delete $self->{disconnectedPool}->{ $c->{id} };

            $self->connectOne($c, sub {
                # at this point we're guaranteed we have a claimable connection...
                # we make a recursive call into claim, knowing it will succeed
                $self->claim($cb);
             });
            return;
        } else {
		    $self->{log}->log("nothing in freepool OR disconnectedpool");
		    $cb->(undef);
        }
        return;
	}

	#$self->{log}->log(scalar(keys(%{$self->{freepool}})) . " connections available");

	my @c = values(%{ $self->{freepool} });
	my $c = $c[0];

	delete $self->{freepool}->{ $c->{id} };

    # if it was in the freepool, it's also could be queued up for disconnection
    # let's make sure that doesn't happen.
    delete $self->{pendingDisconnections}->{ $c->{id} };

	#$self->{log}->log(scalar(keys(%{$self->{freepool}})) . " connections available");

#$c->{state} = "claimed";

	# $self->{log}->log(ref($c));
	# $self->{log}->log(ref($c->{connection}));
	# $self->{log}->log(ref($c->{protocol}));

	$cb->($c);
}

=head2 release

Returns a connection instance back to the pool of free instances.

No return value.

If we have a disconnect time, set an alarm to disconnect this guy.

=cut

sub release {
	my ($self, $c) = @_;
#$c->{state} = "connected";
	$self->{freepool}->{ $c->{id} } = $c;

    $self->{log}->log("releasing!");
	
	my $rcb = $self->{release_cb};

	if ($rcb){
		$rcb->();
	}

    if ($self->{disconnect_after}) {
        $self->{log}->log("setting up disconnection callback...");
        my $w = AnyEvent->timer( after => $self->{disconnect_after}, cb => sub {
            $c->reset();
			$self->{log}->log("after timeout, connection state free->disconnected");
			delete $self->{freepool}->{ $c->{id} };
			$self->{disconnectedPool}->{ $c->{id} } = $c;
        });

        $self->{pendingDisconnections}->{ $c->{id} } = $w;
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
	
	return scalar(keys(%{$self->{freepool}})) + scalar(keys(%{$self->{disconnectedPool}}));
}
