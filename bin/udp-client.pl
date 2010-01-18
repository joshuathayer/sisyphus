#!/usr/bin/perl

use strict;
use Sisyphus::Proto::Newline;
use AnyEvent::Strict;
use Scalar::Util qw/ weaken /;
use IO::Socket;

#my $c = Sisyphus::Connector->new();
#$c->{host} = '127.0.0.1';
#$c->{port} = 8889;
#$c->{protocolName} = "Trivial";
#my $cv = AnyEvent->condvar;
#my $got = 0;
#my $handle;

my $prot = IO::Socket::INET->new(
	Proto=>"udp",
	PeerPort=>8887,
	PeerAddr => "127.0.0.1",
);

$prot->send("image upload\r\n90uohf9asf98safpiuhdp89fhpas98fhdpa9sf.jpg\r\n\r\nrule brittania\r\nrule the waves\r\n\r\n");
