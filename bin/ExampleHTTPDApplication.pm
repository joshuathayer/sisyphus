package ExampleHTTPDApplication;

use strict;
use base 'Sisyphus::Application';

use Data::Dumper;
use IO::AIO;
use AnyEvent::AIO;

# implements a trivial little application

my $responses;

sub new {
	my $class = shift;
	my $self = { };
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

# passed the host and port of the requesting machine,
# and an array of data as passed by the protocol module
sub message {
	my ($self, $host, $port, $dat, $fh) = @_;

	my $req = $dat->[0];

	# $req is an AE::HTTPD::Request instance
	# Request class has methods for talking to the AE loop
	# but we'll do it by hand here to demonstrate the use of Sisyphus
	my $meth = $req->method();
	my $url= $req->url;
	my $params = $req->vars;
	my $headers = $req->headers();

	#my ($meth, $url, $hdr, $content) = @$dat;

	# in the real world, this is where we'd dispatch into real application
	# code to do real things.
	
	# in this case, we'll make sure there is any request body at all, and
	# if so, indicate there is something to respond with

	aio_readdir($url->as_string(), sub {
		my $d = shift;

		my $ret = "<html><head><title>example</title></head><body>";
		$ret .= "Params<br><pre>";
		$ret .= Dumper $params;
		$ret .= "</pre>";
		$ret .= "Headers<br><pre>";
		$ret .= Dumper $headers;
		$ret .= "</pre>";
		$ret .= "Method<br><pre>";
		$ret .= Dumper $meth;
		$ret .= "</pre>";
		$ret .= "URL<br><pre>";
		$ret .= $url;
		$ret .= "</pre>";

		unless ($d) {
			$ret .= "$url is not a directory i could find";
		} else {
			$ret .= join("<br>\n", map("<a href=\"$_\">$_</a>", @$d));	
		}
		print "response is:\n$ret\n";
	
		$responses->{$fh} =
			[200, "OK", {"Content-type" => "text/html",}, "$ret"];
		$self->{client_callback}->([$fh]);	
	});
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
