#!/usr/bin/perl

use strict;
use AnyEvent::Strict;
use Sisyphus::Connector;
use Data::Dumper;

my $c = Sisyphus::Connector->new();
$c->{host} = '127.0.0.1';
$c->{port} = 8889;
$c->{protocolName} = "JSON";
my $cv = AnyEvent->condvar;

$c->{app_callback} = sub {
	my $dat = shift;

	print "received from server:\n";
	print Dumper $dat;

	$cv->send;
};


$c->connect(sub{
	my $message = {
		set_message => 1,
		body => "hello world",
	};

	$c->send($message);

});

$cv->recv;
