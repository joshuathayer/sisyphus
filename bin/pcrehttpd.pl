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
use lib ('/home/joshua/sisyphus/req/IO-AIO-3.3/blib/arch');
use lib ('/home/joshua/sisyphus/req/IO-AIO-3.3/blib/lib');
use lib ('/home/joshua/sisyphus/req/AnyEvent-AIO-1.1/blib/lib/');
use lib ('/home/joshua/sisyphus/req/URI-1.40/blib/lib');

use Sisyphus::Listener;
use Sisyphus::Proto::HTTP;
use AnyEvent::Strict;
use PCREHTTPD;

BEGIN {
	if ($#ARGV < 0) {
		print "Usage: $0 PATH_TO_CONFFILE\n";
		exit;
	}
}

# import PCREConfig namespace
my $confPath = $ARGV[0];
require $confPath;

my $listener = new Sisyphus::Listener;

$listener->{port} = $PCREConfig::port;
$listener->{ip} = $PCREConfig::ip;
$listener->{protocol} = "Sisyphus::Proto::HTTP";
$listener->{application} = PCREHTTPD->new(
	$PCREConfig::module,
	$PCREConfig::re,
	$PCREConfig::httplog,
	$PCREConfig::applog,
);
$listener->listen();

AnyEvent->condvar->recv;
