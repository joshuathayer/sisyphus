package HTTPAppServer;

# this is a Sisyphus Application.
# You give it a module which implementes METHOD_* methods
# When this Application gets messages in the form
# "foo/bar/baz/biff"
# it tries to find the METHOD_foo method if your module,
# and calls it with the rest of the message

use strict;
use base 'Sisyphus::Application';

use Data::Dumper;
use IO::AIO;
use AnyEvent::AIO;

my $responses;

sub new {
	my $class = shift;
	my $app = shift;
	my $self = { };
	$self->{METHODS} = $app;
	require $app . ".pm";
	return(bless($self, $class));
}

sub new_connection {
	my $self = shift;
	print  "new connection\n";
}

sub remote_closed {
	my ($self, $host, $port, $fh) = @_;
	delete $responses->{$fh};
}

sub message {
	my ($self, $host, $port, $dat, $fh) = @_;

	my $req = $dat->[0];

    # $req is an AE::HTTPD::Request instance
    # Request class has methods for talking to the AE loop
    # but we'll do it by hand here to demonstrate the use of Sisyphus
    my $meth = $req->method();
    my $url= $req->url;
    my $params = $req->vars();
    my $headers = $req->headers();

	my @u = split('/',$url->as_string());
	my $m = pop @u;
	$m = $self->{METHODS} . "::METHOD_" . $m;

	if (defined &{$m}) {
		$responses->{$fh} =
			[200, "OK", {"Content-type" => "text/html",}, "you want me to call a method i do know about!"];
		# haha. getting around strict refs. see http://perldoc.perl.org/strict.html
		my $bar = \&{$m};
		$bar->($meth, $u, $params, $headers, sub {
			my ($code, $str, $headers, $cont) = @_;	
			$responses->{$fh} = [$code, $str, $headers, $cont]l
			$self->{client_callback}->([$fh]);	
		});
	} else {
		$responses->{$fh} =
			[404, "NOT_FOUND", {"Content-type" => "text/html",}, "i don't know anything about that url"];
		$self->{client_callback}->([$fh]);	
	}

	return undef;
}

sub get_data {
	my ($self, $fh) = @_;

	unless ($responses->{$fh}) { return; }
	my $v = $responses->{$fh};
	$responses->{$fh} = undef;
	return $v;

	#print "get_data fh $fh\n";
	#print Dumper $responses->{$fh};
	#my $v = join("\r\n", @{$responses->{$fh}});
	#$responses->{$fh} = undef;

	#print "V is:\n$v";
	#return($v);
}

1;
