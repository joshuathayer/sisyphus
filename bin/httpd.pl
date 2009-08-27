#!/usr/bin/perl

use strict;
use lib ('/home/joshua/sisyphus/lib');
use lib ('/home/joshua/sisyphus/req/EV-3.8');
use lib ('/home/joshua/sisyphus/req/AnyEvent-5.112/lib');
use lib ('/home/joshua/sisyphus/req/MySQL-Packet-0.2007054/lib');
use lib ('/home/joshua/sisyphus/req/AnyEvent-HTTP-1.43');
use lib ('/home/joshua/sisyphus/req/AnyEvent-HTTPD-0.82/lib');
use lib ('/home/joshua/sisyphus/req/common-sense-1.0/blib/lib');
use lib ('/home/joshua/sisyphus/req/Object-Event-1.1/lib');


use Sisyphus::Listener;
use Sisyphus::Proto::HTTP;
use AnyEvent::Strict;
use ExampleHTTPDApplication;

my $listener = new Sisyphus::Listener;

$listener->{port} = 8889;
$listener->{ip} = "172.16.5.9";
$listener->{protocol} = "Sisyphus::Proto::HTTP";
$listener->{application} = ExampleHTTPDApplication->new();
$listener->{use_push_write} = 0;
$listener->listen();

AnyEvent->condvar->recv;
