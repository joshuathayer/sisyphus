package Sisyphus::Connector;

use strict;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

use Data::Dumper;
use Sisyphus::Proto::Factory;
use Sislog;
use Scalar::Util qw/ weaken /;

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
		response_handler => undef,
		connected => undef,
		log => Sislog->new({use_syslog=>1, facility=>"Sisyphus-Connector"}),

	};

	bless($self, $class);
	my $wself = $self;
	weaken $wself;

	$self->{log}->open();
	$self->{on_error} = sub {
		my ($err) = @_;
		$wself->onError($err);
	};
	$self->{server_closed} = sub {
		$wself->serverClosed();
	};

	return $self;
}

sub onError {
	my ($self, $err) = @_;

	$self->{connected} = undef;
	$self->{log}->log("error on connection with $self->{host}:$self->{port}. connection considered closed.");
}

sub serverClosed {
	my $self = shift;

	
	$self->{log}->log("server closed connection with $self->{host}:$self->{port}.");
	$self->{connected} = undef;

	$read_watcher = undef;
}

sub connectSync {
	my $self = shift;

	my $cv = AnyEvent->condvar;

	$self->connect(
		sub {
			$cv->send;
		}
	);

	$cv->recv;
}

sub connect {
	my ($self, $cb) = @_;

	weaken $self;

	$self->{log}->log("trying to connect to $self->{host}, $self->{port}");

	tcp_connect $self->{host}, $self->{port}, sub {
		$self->{fh} = shift;
		unless (defined ($self->{fh})) {
			$self->{log}->log("connect failed.");
			$self->{on_error}->();
			return;
		};

		$self->{protocol} = Sisyphus::Proto::Factory->instantiate($self->{protocolName}, $self->{protocolArgs});
		unless (ref($self->{protocol})) {
			$self->{log}->log("could not instantiate protocol " . $self->{protocolName});
		}

		$self->{protocol}->{app_callback} = $self->{app_callback};

		$self->{protocol}->{handle} = AnyEvent::Handle -> new (
			fh => $self->{fh},
			on_error => $self->{on_error},
			on_eof => $self->{on_eof},
		);

		$self->{connected} = 1;
		
		# call protocol's "on_connect" function, which initiates 
		# and starts the handler
		$self->{protocol}->on_connect( sub {

			$cb->($self);
		} );
	};

}	

sub send {
	my ($self, $data) = @_;

	$self->{protocol}->frame($data);
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
