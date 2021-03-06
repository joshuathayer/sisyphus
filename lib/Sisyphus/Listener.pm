package Sisyphus::Listener;
use strict;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Data::Dumper;
use Scalar::Util qw/ weaken /;
#use Devel::Cycle;

use constant DEBUG => 1;

=head1 NAME

Sisyphus::Listener - Listener side of Sisyphus framework

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Sisyphus::Listener;

    my $foo = Sisyphus::Listener->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 FUNCTIONS

=head2 function1

=cut

sub new {
	my $class = shift;

	my $self = {
		port => 0,
		ip => '',
		protocol => undef,
		application => undef,
		use_push_write => 1,
		livecon => 0,
		clients => {},
		outbufs => {},
		stash => {},
		name => '',
	};

	return(bless($self, $class));
}

=head2 function1

listen()

Creates an AnyEvent tcp_server, listening on the configured port,
speaking the specified protocol, and dispatching the the provided
Application.

=cut

sub listen {
	my $self = shift;

	# set up application's client_callback. this is how the application lets
	# us know of data ready for our clients
	#$self->{application}->{client_callback} = sub { $self->client_callback(@_) };

	# jt 10/2010- no longer the case. when we call message() in the application,
	# we pass along the callback then. so we can support one application instance
	# across multiple listener instances (to support multiple protocols in one app)

	# actually no. we notify our application that is has a new listener, and let the 
	# application give us a sub to call when we have data for it
	#$self->{application_message_callback} = $self->{application}->register_listener($self);

	# no, no. we pass a ref to ourself in the call to register_listener,
	# so the app has a ref to us and our client_callback so it can send 
	# messages through us whenever it wants to. also, we send a ref to
	# ourself when we call message(), so it knows who to send messages
	# back through
	$self->{application}->register_listener($self);

	tcp_server $self->{ip}, $self->{port}, sub {
		my ($fh, $host, $port) = @_;

		my $cid = "$host:$port";
		warn("a new connection, ID $cid") if DEBUG;

		$self->{livecon} += 1;

		if ($self->{clients}->{$cid}) {
			die("huh, data on a socket that should be handled by an existing handle");
		}

		warn("instantiating and configuring a new protocol instance for $cid");
		$self->{clients}->{$cid}->{host} = $host;	
		$self->{clients}->{$cid}->{port} = $port;	
		$self->{clients}->{$cid}->{proto} = $self->{protocol}->new();

		# how the proto gets messages to the app. we make this a closure
		# to enable us to send the cid along to the app.
		$self->{clients}->{$cid}->{proto}->{app_callback} = sub {
			$self->send_app_message($cid, @_);
		};

		# how protocol-triggered socket closures get bubbled back to me
		# protocol calls $self->{close_callback}->() 
		$self->{clients}->{$cid}->{proto}->{close_callback} = sub {
			$self->{application}->remote_closed($host, $port, $cid);
			$self->{clients}->{$cid}->{handle}->{fh}->close();

			delete $self->{clients}->{$cid};

			$self->{livecon} -= 1;
		};

		# make the handle
		$self->{clients}->{$cid}->{handle} = AnyEvent::Handle->new(
			fh => $fh,
			on_error => sub {
				my ($hdl, $fatal, $msg) = @_;
				print "error talking to client $cid. probably remote closed.\n";
				# we notify our application and our protocol of the closed connection
				# hmm this line was erroring- proto already undefed somehow?
				# for some reason, we often get here after
				# protocol-triggered disconnect (after
				# close_callback is called). in that case, we've
				# already done all the shutdown work, so we can, i
				# think, essentially ignore this
				if ($self->{clients}->{$cid}) {
					$self->{clients}->{$cid}->{proto}->on_client_disconnect();	
					$self->{application}->remote_closed($host, $port, $cid);

					# the proto disconnect handler can potentially 
					# tickle close_callback, above, in which case
					# we may have already closed the socket by here
					if ($self->{clients}->{$cid}) {
						delete $self->{clients}->{$cid};
						$self->{livecon} -= 1;
					} else { 
						 print "feels like close_callback closed socket already\n";
					}
				}
			},
			on_eof => sub {
				# we notify our application and our protocol of the closed connection
				$self->{clients}->{$cid}->{proto}->on_client_disconnect();	
				$self->{application}->remote_closed($host, $port, $cid);

				# see comment above- on_client_disconnect may have
				# already done this stuff:
				if ($self->{clients}->{$cid}) {
					delete $self->{clients}->{$cid};
					$self->{livecon} -= 1;
				}
			},
		);

		# give the proto instance this handle, which it will use to read
		# from and write to
		$self->{clients}->{$cid}->{proto}->{handle} = $self->{clients}->{$cid}->{handle};

		# alert application to new connection
		$self->{application}->new_connection($host, $port, $cid);

		# start the protocol ball rolling.
		$self->{clients}->{$cid}->{proto}->on_client_connect();	
	}, sub {
		my ($fh, $thishost, $thisport) = @_;

		print "server listening on $thishost $thisport\n";
    # per anyevent::socket dox, we return the length of our listening queue
    return 200;
	};

}

# can be called at any time by a Protocol instance. Asynchronous notification
# of data available for our Application
sub send_app_message {
	my ($self, $cid, @dat) = @_;

	my $host = $self->{clients}->{$cid}->{host};
	my $port= $self->{clients}->{$cid}->{port};

	my $dat = \@dat;

	# apps whih have disparate listeners speaking disparate protocols might
	# want to normalize messages into a standard format. let that happen here.
	# take a closer look at params. XXX 10/2010
	if ($self->{interface}) {
		$self->{interface}->message($host, $port, $dat, $cid, $self->{stash}, sub {
			my ($dat) = @_;
			$self->{application}->message($host, $port, $dat, $cid, $self->{stash}, $self);
		});
		return;
	}

	# we give the app the host, port, and cid at connection time.
	# we don't need to do that again and again. and, stash is useless
	# XXX fix that shit
	# actually no. in the UDP world, it makese sense.
	$self->{application}->message($host, $port, $dat, $cid, $self->{stash}, $self);
	# thinking about "message normalization", in servers where there are multiple
	# listeners and thus multiple potential message formats. we want the call to 
	# message() to be as simple as possible	
}

# called at any time by our Application instance. indicates app has data ready 
# for this client
sub client_callback {						
	my ($self, $w) = @_;

	warn("here in client_callback") if DEBUG;

	# if we're here, our app has indicated that it has something to send on this 
	# filehandle!
	foreach my $writable (@$w) {
		warn("writable $writable") if DEBUG;

		my $m = $self->{application}->get_data($writable);
		while ($m) {
			if ($self->{interface}) {
				$self->{interface}->frame($m, sub {
					$self->{clients}->{ $writable }->{proto}->frame(@_[0]);
				});
			} else {
					$self->{clients}->{ $writable }->{proto}->frame($m);
			}
			$m = $self->{application}->get_data($writable);
		}
	}
}

=head1 AUTHOR

Joshua Thayer, C<< <joshuamilesthayer at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-sisyphus-listener at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Sisyphus-Listener>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Sisyphus::Listener


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Sisyphus-Listener>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Sisyphus-Listener>


=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Sisyphus-Listener>

=item * Search CPAN

L<http://search.cpan.org/dist/Sisyphus-Listener>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2009 Joshua Thayer, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Sisyphus::Listener
