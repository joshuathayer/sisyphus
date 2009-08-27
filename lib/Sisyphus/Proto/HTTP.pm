package Sisyphus::Proto::HTTP;
use strict;
use base 'AnyEvent::HTTPD::HTTPConnection';

use Data::Dumper;
use Date::Format;

# this is basically a shim between the Sisyphus framework and
# AnyEvent::HTTPD::HTTPConnection. This class inherits from
# AE:H:HTTPConnection in order to avoid calling that class's 
# constructor, which tries to take control by creating its own
# Handle object (which, in the Sisyphus universe, is done in the
# Listener.

sub new {
	my $this  = shift;
	my $class = ref($this) || $this;
	my $self  = { @_ };
	print "class $class\n";
	bless $self, $class;

	$self->{request_timeout} = 60
	unless defined $self->{request_timeout};

	return $self
}

# called by framework when a client connects.
# a bunch of the things done in AE::H::HTTPConnection's
# constructor are done here instead (register the "request"
# callback, assign the handle)
sub on_client_connect {
	my $self = shift;

	print "hello from on_client_connect\n";

	$self->reg_cb(request => sub {
		# stolen from A::HTTPD.pm's new():
		my ($con, $meth, $url, $hdr, $cont) = @_;
		$self->request($con, $meth, $url, $hdr, $cont);
	});

	# at this point, $self->{handle} has been set to a new AE::Handle object. 
	# AE::HTTPD::HTTPConnection (from which this class descends) expects that
	# as $self->{hdl}. so...
	$self->{hdl} = $self->{handle};

	# now, we let AE::HTTPD::HTTPConnetion run the show
	$self->push_header_line;
}

## just pull bytes off the wire and give them to the httpd instance
#sub consume {
#	my $self = shift;
#	my $handle = $self->{handle};
#	print "consume!\n";
#	$handle->on_read(sub {
#		#my ($handle, $in) = @_;
#		my $handle = shift;
#		print "in "  . $handle->{rbuf} ."\n";
#		$self->{HTTPConnection}->handle_data(\$handle->{rbuf});
#	});
#}

sub request {
	# called by A::H::HTTPConnection on request
	# so, we have a full HTTP request, we wish to send it to our application
	my ($self, $con, $meth, $url, $hdr, $cont)  = @_;

	print "in HTTP::request\n";
	#print Dumper $con;
	#print Dumper $meth;
	#print Dumper $url;
	#print Dumper $hdr;

	$self->{app_callback}->($meth, $url, $hdr, $cont);
}

sub frame {
	# much stolen from A::H::HTTPConnection
	my ($self, $r) = @_;
	print Dumper $r;
	my ($code, $msg, $hdr, $content) = @$r;
	
	my $res = "HTTP/1.0 $code $msg\015\012";
	$hdr->{'Expires'} = $hdr->{'Date'} = time2str time;
	$hdr->{'Cache-Control'} = "max-age=0";
	$hdr->{'Content-Length'} = length $content;

	while (my ($h, $v) = each %$hdr) {
		$res .= "$h: $v\015\012";
	}
	$res .= "\015\012";
	$res .= $content;

	$self->{handle}->push_write($res);

}
1;
