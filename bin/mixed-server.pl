#!/usr/bin/perl

use strict;

use Sisyphus::Listener;
use Sisyphus::Proto::JSON;
use Sisyphus::Proto::HTTP;
use AnyEvent::Strict;
use ExampleJSONApplication;
use ExampleHTTPDApplication;

my $stash = {};

my $listener = new Sisyphus::Listener;

$listener->{port} = 8889;
$listener->{ip} = "127.0.0.1";
$listener->{protocol} = "Sisyphus::Proto::JSON";
$listener->{application} = ExampleJSONApplication->new();
$listener->{stash} = $stash;
$listener->listen();

my $hlistener = new Sisyphus::Listener;

$hlistener->{port} = 8880;
$hlistener->{ip} = "127.0.0.1";
$hlistener->{protocol} = "Sisyphus::Proto::HTTP";
$hlistener->{application} = ExampleHTTPDApplication->new();
$hlistener->{stash} = $stash;
$hlistener->listen();

AnyEvent->condvar->recv;

