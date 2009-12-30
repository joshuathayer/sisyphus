#!/usr/bin/perl

use strict;

use Sisyphus::Listener;
use Sisyphus::Proto::HTTP;
use AnyEvent::Strict;
use ExampleHTTPDApplication;

my $listener = new Sisyphus::Listener;

$listener->{port} = 8889;
$listener->{ip} = "127.0.0.1";
$listener->{protocol} = "Sisyphus::Proto::HTTP";
$listener->{application} = ExampleHTTPDApplication->new();
$listener->{use_push_write} = 0;
$listener->listen();

AnyEvent->condvar->recv;
