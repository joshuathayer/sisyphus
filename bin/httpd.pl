#!/usr/bin/perl

use strict;

use Sisyphus::Listener;
use Sisyphus::Proto::HTTP;
use AnyEvent::Strict;
use ExampleHTTPDApplication;

my $listener = new Sisyphus::Listener;

$listener->{port} = 8889;
$listener->{ip} = "172.16.0.8";
$listener->{protocol} = "Sisyphus::Proto::HTTP";
$listener->{application} = ExampleHTTPDApplication->new();
$listener->{use_push_write} = 0;
$listener->listen();

AnyEvent->condvar->recv;
