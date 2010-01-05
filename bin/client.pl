#!/usr/bin/perl

use strict;
use Sisyphus::Proto::Trivial;
use AnyEvent::Strict;
use Sisyphus::Connector;
use Scalar::Util qw/ weaken /;

my $c = Sisyphus::Connector->new();
$c->{host} = '127.0.0.1';
$c->{port} = 8889;
$c->{protocolName} = "Trivial";
my $cv = AnyEvent->condvar;
my $got = 0;
my $handle;

$c->{app_callback} = sub {
	my $dat = shift;
	$got++;
		print "client got: $dat\n";
	if ($got > 999) {
		$cv->send;
	}
};


# ah. this sets up a circular ref.
weaken(my $wc = $c);
$c->connect(sub{
	my $n = 0;

	while ($n < 1000) {
		$wc->send("hi there");
		print "!";
		$n++;
	}

	print "carrying on\n";
});

$cv->recv;

