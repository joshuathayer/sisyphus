package Sisyphus::Listener;
use strict;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Data::Dumper;
use Scalar::Util qw/ weaken /;
#use Devel::Cycle;

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
	$self->{application}->{client_callback} = sub { $self->client_callback(@_) };

	tcp_server $self->{ip}, $self->{port}, sub {
		my ($fh, $host, $port) = @_;

		$self->{livecon} += 1;

		my $cid = "$host:$port";

		if ($self->{clients}->{$cid}) {
			print "huh, data on a socket that should be handled by the handler.\n";
			return;
		}

		# a new connection from a client.
		$self->{clients}->{$cid}->{proto} = $self->{protocol}->new();

		# how the proto gets messages to the app
		$self->{clients}->{$cid}->{proto}->{app_callback} = sub { $self->app_callback($cid, @_) };

		# how protocol-triggered socket closures get bubbled back to me
		# protocol calls $self->{close_callback}->() 
		$self->{clients}->{$cid}->{proto}->{close_callback} = sub {
			$self->{application}->remote_closed($host, $port, $cid);
			$self->{clients}->{$cid}->{handle}->{fh}->close();

			delete $self->{clients}->{$cid};

			$self->{livecon} -= 1;
		};

		$self->{clients}->{$cid}->{host} = $host;	
		$self->{clients}->{$cid}->{port} = $port;	

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


		$self->{clients}->{$cid}->{proto}->{handle} = $self->{clients}->{$cid}->{handle};

		# alert application to new connection
		$self->{application}->new_connection($host, $port, $cid);

		# start the protocol ball rolling.
		$self->{clients}->{$cid}->{proto}->on_client_connect();	
	}, sub {
		my ($fh, $thishost, $thisport) = @_;
		print "server listening on $thishost $thisport\n";
	};

	weaken $self;
	#Devel::Cycle::find_cycle($self);
}

# can be called at any time by a Protocol instance. Asynchronous notification
# of data available for our Application
sub app_callback {
	my ($self, $fh, @dat) = @_;

	my $host = $self->{clients}->{$fh}->{host};
	my $port= $self->{clients}->{$fh}->{port};

	#Devel::Cycle::find_cycle($self);

	$self->{application}->message($host, $port, \@dat, $fh);
}

# called at any time by our Application instance. indicates app has data ready 
# for this client
sub client_callback {						
	my $self = shift;
	my $w = shift;

	# if we're here, our app has indicated that it has something to send on this 
	# filehandle!
	foreach my $writable (@$w) {
		my $m = $self->{application}->get_data($writable);
		while ($m) {
			$self->{clients}->{ $writable }->{proto}->frame($m);
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
