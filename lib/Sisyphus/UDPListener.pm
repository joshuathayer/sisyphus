package Sisyphus::UDPListener;

use strict;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Data::Dumper;
use Scalar::Util qw/ weaken /;
use IO::Socket;
use Devel::Cycle;

=head1 NAME

Sisyphus::UDPListener - A UDP Listener for the Sisyphus framework

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
		stash => {},
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

	# much stolen from AnyEvent::DNS.
	weaken(my $wself = $self);

	# set up application's client_callback. this is how the application lets
	# us know of data ready to send
	$self->{application}->{client_callback} = sub {
		$self->client_callback(@_)
	};

	# we will feed bytes into this instance...
	$self->{proto} = $self->{protocol}->new();

	# ...and it will let us know of messages for our application via this
	$self->{proto}->{app_callback} = sub { $self->app_callback(@_) };

	my $sock = IO::Socket::INET->new(
		LocalAddr => $self->{ip},
		LocalPort => $self->{port}, 
		Proto => 'udp') or die "socket: $@";


	$self->{rw} = AE::io $sock, 0, sub {
		if (my $peer = recv $sock, my $pkt, 4096, 0) {
			my ($ppt, $pip) = unpack_sockaddr_in($peer);
			my $dotquad = inet_ntoa($pip);
			$wself->{proto}->datagram($pkt, inet_ntoa($pip), $ppt);
		}
	};

	print "UDP server listening on $self->{ip}:$self->{port}\n";
}

# this is passed data from the Protocol, when the protocol wants to get data
# to the application. it's passed:
# origin $host, origin $port, $data
# we wish to also send our app a ref to our 'stash'
sub app_callback {
	my $self = shift;
	$self->{application}->message(@_, $self->{stash});
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
