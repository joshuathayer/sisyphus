package Sisyphus::Listener;
use strict;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Data::Dumper;

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

# this is more or less lifted directly from the fcgi module.
sub listen {
	my $self = shift;
	my $clients = $self->{clients};

	# set up application's client_callback. this is how the application lets
	# us know of data ready for our clients
	$self->{application}->{client_callback} = sub { $self->client_callback(@_) };

	tcp_server $self->{ip}, $self->{port}, sub {
		my ($fh, $host, $port) = @_;
		$self->{livecon} += 1;

		my $read_watcher;
		$read_watcher = AnyEvent->io(
			fh=>$fh,
			poll=>'r',
			cb => sub {
				my $in;
				unless (defined($in)) { $in = ''; }
				#print "read watcher! alert!!\n";

				unless($clients->{$fh}) {
					# print "trying to make new protocol for this socket.\n";
					$clients->{$fh}->{proto} = $self->{protocol}->new();
					$clients->{$fh}->{proto}->{app_callback} = sub { $self->app_callback($fh, @_) };
					$clients->{$fh}->{host} = $host;	
					$clients->{$fh}->{port} = $port;	

					# make a handle, too
					$clients->{$fh}->{handle} = AnyEvent::Handle->new(
						fh => $fh,
						on_error => sub { warn "error talking to client!"; },
						on_eof => sub { warn "client disconnected!"; },
						on_drain => sub {
									# print "on_drain!\n";
									my $handle = shift;
									my $fh = $handle->{fh};
									unless ($fh) { print "on_drain was passed undef fh...\n"; return undef; }
									my $m = $self->{application}->get_data($fh);
									unless ($m) { return undef; } # we have a writable fh, but nothing to send... 
									$m = $clients->{$fh}->{proto}->frame($m);

									# we seem to be called here very early, like before
									# $clients->{$fh}->{handle} is set. 
									unless (defined ($clients->{$fh}->{handle})) { return; }

									# getting in to the internals of anyevent...
									#my $wblen = length($clients->{$fh}->{handle}->{wbuf});
									#if ($wblen < 1024) {
									#	print "wbuf len $wblen\n";
										$clients->{$fh}->{handle}->push_write($m);	
									#} else {
									#	print "avoiding push_write, as buffer is too long already.\n";
									#}
								},
					);

				}

				#print "want $clients->{$fh}->{proto}->{bytes_wanted} bytes!\n";
				my $len = sysread $fh, $in,
				    $clients->{$fh}->{proto}->{bytes_wanted}, length $in;
				#print "got $len bytes!\n";

				if ($len == 0) {
					$self->{application}->remote_closed($host, $port, $fh);
					#print DUMPER "closing connection for client $fh\n";
					delete $clients->{$fh};
					close $fh;
					undef $read_watcher;
					$self->{livecon} -= 1;
				} elsif ($len > 0) {
					# we have bytes. the client wanted bytes. append them
					# to its buffer. alert the client it has new bytes.
					# if it has a full message, it'll return it.
					
					$clients->{$fh}->{proto}->{buffer} .= $in;
					my $r = $clients->{$fh}->{proto}->consume();
					if ($r) {
						$self->{application}->message($host, $port, $r, $fh);

						#my $w = $self->{application}->message($host, $port, $r, $fh);
						#print Dumper $w;
						
						#if ($w) {
						#	# we've given our application some data,
						##	# and if we're here, it's indicated that it has something to send on this 
						#	# filehandle!
						#	foreach my $writable (@$w) {
						#		#print "looking at writables\n";
						#		#print Dumper $writable;
						#
						#		if ($self->{use_push_write}) {	
						#			my $m = $self->{application}->get_data($writable);
						#			unless ($m) { next; }
						#			$m = $clients->{ $writable }->{proto}->frame($m);
						#			$clients->{ $writable }->{handle}->push_write($m);	
						#		} else {
						#			# we only want to peel off a message when the write handle is writable	
						#			$self->write_till_empty($writable);
						#		}
						#	}
						#}
					}
					return undef;

				} else {
					print STDERR "error on socket! $fh\n";
					delete $clients->{$fh};
					close $fh;
					undef $read_watcher;
					$self->{livecon} -= 1;
				}
	
				# reference the callback within the callback, so it
				# never gets GCd
				if (0) {
					undef $read_watcher;
				}
			},
		);
	}, sub {
		my ($fh, $thishost, $thisport) = @_;
		#print STDERR "bound to $thishost, $thisport\n";
	};
	
}

# ask application for data bound for a particular FH until it has no more data to give
# but only at the rate that our socket can accept it (ie, don't act like push_write and
# buffer everything in a scalar
sub write_till_empty {
	my ($self, $writable) = @_;

	unless(defined($self->{outbufs}->{$writable})) {
		$self->{outbufs}->{$writable} = '';
	}

	my $w; $w = AnyEvent->io (fh => $writable, poll => 'w', cb => sub {
		# if we don't have anything in the buffer, go get exactly one message
		unless (length($self->{outbufs}->{$writable})) {
			print "empty wbuf, getting a message from application, writable is\n";
			print Dumper $writable;
			my $m = $self->{application}->get_data($writable);
			$m = $self->{clients}->{$writable}->{proto}->frame($m);
			$self->{outbufs}->{$writable} .= $m;
			#print "length now " . length($self->{outbufs}->{$writable}) . "\n";
			#Hexdump::hexdump($self->{outbufs}->{$writable});
		}
		# if we have data in the buffer, try to send it
		if (length($self->{outbufs}->{$writable})) {
			my $len = syswrite $writable, $self->{outbufs}->{$writable};
			#print "wrote $len bytes!\n";
			if ($len > 0) {
				substr $self->{outbufs}->{$writable}, 0, $len, "";
				if (length($self->{outbufs}->{$writable})) {
					$self->write_till_empty($writable);
				} else {
					undef $w;
				}
			}
		} else {
			# if we don't have any data, we're done with this watcher!
			undef $w;
		}
	});
}

# can be called at any time by a Protocol instance. Asynchronous notification
# of data available for our Application
sub app_callback {
	my ($self, $fh, @dat) = @_;

	print "dat in app_callback:\n";
	print Dumper \@dat;

	my $host = $self->{clients}->{$fh}->{host};
	my $port= $self->{clients}->{$fh}->{port};

	my $w = $self->{application}->message($host, $port, \@dat, $fh);
}

# called at any time by our Application instance. indicates app has data ready 
# for this client
sub client_callback {						
	my $self = shift;
	my $w = shift;

	my $clients = $self->{clients};

	# if we're here, our app has indicated that it has something to send on this 
	# filehandle!
	foreach my $writable (@$w) {
		print "looking at writables\n";
		print Dumper $writable;

		if ($self->{use_push_write}) {	
			my $m = $self->{application}->get_data($writable);
			print "did i get data? $m\n";
			unless ($m) { next; }
			$m = $clients->{ $writable }->{proto}->frame($m);
			$clients->{ $writable }->{handle}->push_write($m);	
		} else {
			# we only want to peel off a message when the write handle is writable
			print "calling write_till_empty\n";
			$self->write_till_empty($writable);
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
