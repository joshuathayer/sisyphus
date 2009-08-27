package ExampleHTTPDApplication;

use strict;
use base 'Sisyphus::Application';

use Data::Dumper;

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
	
	print  "$host closed connection!\n";
}

sub message {
	my ($self, $host, $port, $dat, $fh) = @_;

	my ($meth, $url, $hdr, $content) = @$dat;

	# in the real world, this is where we'd dispatch into real application
	# code to do real things.
	
	# in this case, we'll make sure there is any request body at all, and
	# if so, indicate there is something to respond with

	if ($url) {	
		$responses->{$fh} =
			[200, "OK", {}, "hello from a trivial server. you wanted $url."];

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
