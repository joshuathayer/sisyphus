# example sisyphus client

use strict;
use lib ("/home/joshua/projects/sisyphus/lib/");

use AnyEvent::Strict;
use Sisyphus::Connector;
use Data::Dumper;
use Sisyphus::Proto::Factory;
use JSON;

my $message_id = 0;

my $ac  = new Sisyphus::Connector;
$ac->{host} = "127.0.0.1";
$ac->{port} = 8889;
$ac->{protocolName} = "Trivial";

$ac->{app_callback} = sub {
	my $message = shift;
	print "i received a message:\n";
	print Dumper $message;
};

my $cv = AnyEvent->condvar;
$ac->connectAsync(sub { print STDERR "connected.\n"; $cv->send; });
$cv->recv;

# set a record
my $o = {
	command => "set",
	key => "bonham",
	data => {
		first => "John",
		last => "Bonham",
		band => "Zeppelin",
		albums => [
			"Houses of the Holy","IV"
		],
	},
};
			
$ac->send(to_json($o));

# get a record
my $o = {
	command => "get",
	key => "bonham",
};
$ac->send(to_json($o));

$ac->send($json);
#$ac->send($json);

AnyEvent->condvar->recv;
