package Sisyphus::Connector;

use strict;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

use Data::Dumper;

=head1 NAME

Sisyphus::Connector - The great new Sisyphus::Connector!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Sisyphus::Connector;

    my $foo = Sisyphus::Connector->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 FUNCTIONS

=head2 function1

=cut


my $read_watcher;

sub new {
	my $class = shift;
	my $self = {
		host => '',
		port => 0,
		protocol => undef,
		application => undef,
		on_error => \&onError,
		generator => undef,
		server_closed => \&serverClosed,
	};
	return(bless($self, $class));
}

sub onError {
	die("there was an error. alas.");
}

sub serverClosed {
	my $self = shift;

	print "the server closed the connection. alas.\n";

	$read_watcher = undef;
}

sub connect {
	my $self = shift;

	my $cv = AnyEvent->condvar;

	$self->connectAsync(
		sub {
			# print STDERR "connected.\n";
			$cv->send;
		}
	);

	$cv->recv;
}



sub connectAsync {
	my $self = shift;
	my $cb = shift;

	tcp_connect $self->{host}, $self->{port}, sub {
		$self->{fh} = shift;
		unless (defined ($self->{fh})) {
			print STDERR "connect failed.\n";
			$self->{on_error}->();
		};

		$self->{handle} = AnyEvent::Handle -> new (
			fh => $self->{fh},
			on_error => $self->{on_error},
			on_eof => $self->{on_eof},
		);
		# we're set up with "TrivialProtocol" (as a string"),
		# we want a real object. so we instantiate here
		$self->{protocol} = $self->{protocol}->new();
		#print Dumper $self->{protocol};

		$self->init_reader();

		$cb->($self->{fh});
	};
}	

sub init_reader {
	my $self = shift;

	$read_watcher = AnyEvent->io(
		fh => $self->{fh},
		poll => 'r',
		cb => sub {
			my $in;
			unless(defined($in)) { $in = ''; }
			my $len = sysread $self->{fh}, $in, $self->{protocol}->{bytes_wanted}, length $in;
			if  ($len == 0) {
				$self->{server_closed}->();
			} elsif ($len > 0) {
				$self->{protocol}->{buffer} .= $in;
				my $r = $self->{protocol}->consume();
				if ($r) {
				
					$self->{response_handler}->($r);

				}
			} else {
				die("error on socket");
			}

			#if (0) { undef $read_watcher; }
		},
	);

}

sub _send {
	my $self = shift;

	$self->{handle}->on_drain(undef);
	$self->{handle}->push_write( $self->{writeBuffer} );
	$self->{writeBuffer} = '';
}

sub send {
	my $self = shift;
	my $message = shift;


	my $framed = $self->{protocol}->frame($message);
	$self->{writeBuffer} .= $framed;

	$self->{handle}->on_drain( $self->_send );
}

sub generator {
	my $self = shift;
	my $cb = shift;

	if ($cb) {
		$self->{generator} ||= AnyEvent->idle(
			cb => $cb,
		);
	} else {
		undef $self->{generator};
	}
}

=head1 AUTHOR

Joshua Thayer, C<< <joshuamilesthayer at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-sisyphus-connector at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Sisyphus-Connector>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Sisyphus::Connector


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Sisyphus-Connector>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Sisyphus-Connector>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Sisyphus-Connector>

=item * Search CPAN

L<http://search.cpan.org/dist/Sisyphus-Connector>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2009 Joshua Thayer, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of Sisyphus::Connector
