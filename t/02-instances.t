#!perl -T

package TestApplication;

use strict;

# implements a trivial little application
sub new {
        my $class = shift;
        my $self = { };
	my $in = '';
        return(bless($self, $class));
}

sub new_connection {
        my $self = shift;
        my @rest = @_;
}

sub remote_closed {
        my ($self, $host, $port, $fh) = @_;
}

sub message {
        my ($self, $host, $port, $message, $fh) = @_;

        # we return this filehandle- this will indicate to Sisyphus that we have
        # something to send back to the client. in this example case, we'll just
        # return a simple message
	$self->{in} = $message->[0];

        $self->{client_callback}->([$fh]);
}

sub get_data {
        my ($self, $fh) = shift;

	my $out = $self->{in};
	$self->{in} = undef;

        return($out);
}

1;

package main;

use Test::More tests => 5;
use IO::Socket::INET;
use AnyEvent;

use Sisyphus;
use Sisyphus::Proto::HTTP;
use Sisyphus::Proto::Mysql;
use Sisyphus::Proto::Trivial;
use Sisyphus::Proto::FastCGI;


BEGIN {
        use_ok( 'Sisyphus::Listener');
        use_ok( 'Sisyphus::Connector');
}

my $listener = new Sisyphus::Listener;

ok( $listener,		'Listener instance' );

$listener->{ip} = "127.0.0.1";
$listener->{port} = 8989;
$listener->{protocol} = "Sisyphus::Proto::Trivial";
$listener->{application} = TestApplication->new();
$listener->listen();

my $connector = new Sisyphus::Connector;
ok( $connector,		'Connector instance' );

my $ret;
$connector->{host} = "127.0.0.1";
$connector->{port} = 8989;
$connector->{protocolName} = "Trivial";
my $cv = AnyEvent->condvar;
$connector->{app_callback} = sub {
	($ret) = @_;
	$cv->send;
};
$connector->connect( sub {
	my $c = shift;
	$c->send('hello');
});
$cv->recv;
is ($ret, 	"hello");
