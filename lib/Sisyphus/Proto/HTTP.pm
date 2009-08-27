package Sisyphus::Proto::HTTP;
use strict;
use base 'AnyEvent::HTTPD::HTTPConnection';

use Data::Dumper;
use Date::Format;

# this is basically a shim between the Sisyphus framework and
# AnyEvent::HTTPD::HTTPConnection. This class inherits from
# AE:H:HTTPConnection and specifically avoids calling that class's 
# constructor, which tries to take control by creating its own
# Handle object (which, in the Sisyphus universe, is done in the
# Listener).

sub new {
	my $this  = shift;
	my $class = ref($this) || $this;
	my $self  = { @_ };
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

	$self->reg_cb(request => sub {
		# stolen from A::HTTPD.pm's new():
		my ($con, $meth, $url, $hdr, $cont) = @_;
		$self->request($con, $meth, $url, $hdr, $cont);
	});

	# ok wow. when AE:H:HTTPConnection is done sending its response,
	# it indirectly triggers a "disconnect" event (via do_disconnect).
	# we need to let our Listener know of the closed connection, so it 
	# can do its own cleanup
	$self->reg_cb (disconnect => sub {
		#print "in disconnect callback!\n";
		$self->{close_callback}->();
		##print "back from calling close_callback!\n";
	});


	# at this point, $self->{handle} has been set to a new AE::Handle object. 
	# AE::HTTPD::HTTPConnection (from which this class descends) expects that
	# as $self->{hdl}. so...
	$self->{hdl} = $self->{handle};

	# now, we let AE::HTTPD::HTTPConnetion run the show
	$self->push_header_line;
}

# called by framework on client error/disconnect
# we call AE:HTTPD::HTTPConnection's cleanup/close handler
sub on_client_disconnect {
	my $self = shift;
	#print "in on_client_disconnect!\n";

	$self->do_disconnect;
}

sub request {
	# called by A::H::HTTPConnection on request
	# so, we have a full HTTP request, we wish to send it to our application
	my ($self, $con, $meth, $url, $hdr, $cont)  = @_;

	# this is how we get massages back to the application
	$self->{app_callback}->($meth, $url, $hdr, $cont);
	#print "back from calling app callback\n";
}

sub frame {
	# much stolen from A::H::HTTPConnection
	my ($self, $r) = @_;
	my ($code, $msg, $hdr, $content) = @$r;

	$self->response($code, $msg, $hdr, $content);
	#print "back from calling response\n";
}
1;
