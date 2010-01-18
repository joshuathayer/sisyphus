#!/usr/bin/perl

use strict;

use Sisyphus::UDPListener;
use Sisyphus::Proto::Newline;
use AnyEvent::Strict;
use ExampleUDPApplication;

my $listener = new Sisyphus::UDPListener;

$listener->{port} = 8887;
$listener->{ip} = "127.0.0.1";
$listener->{protocol} = "Sisyphus::Proto::Newline";
$listener->{application} = ExampleUDPApplication->new();
$listener->listen();

AnyEvent->condvar->recv;

