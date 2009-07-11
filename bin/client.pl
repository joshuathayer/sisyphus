# example sisyphus client

use strict;
use lib ("/home/joshua/projects/sisyphus/lib/");

use AnyEvent::Strict;
use Sisyphus::Connector;
use Data::Dumper;
use Sisyphus::Proto::Trivial;

my $message_id = 0;

my $ac  = new Sisyphus::Connector;
$ac->{host} = "192.168.1.88";
$ac->{port} = 8889;
$ac->{protocol} = "Sisyphus::Proto::Trivial";

$ac->{response_handler} = sub {
	my $message = shift;
	print "i received a message:\n$message\n\n";
};

my $cv = AnyEvent->condvar;
$ac->connectAsync(sub { print STDERR "connected.\n"; $cv->send; });
$cv->recv;

$ac->send("hello dolly");

AnyEvent->condvar->recv;
