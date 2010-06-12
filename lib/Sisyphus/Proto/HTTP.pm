package Sisyphus::Proto::HTTP;
use strict;
use base 'AnyEvent::HTTPD::HTTPConnection';

use Data::Dumper;
use Date::Format;
use AnyEvent::HTTPD::Request;
use URI;
use Scalar::Util qw/weaken/;
use Devel::Cycle;

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

	($self->{request_timeout} = 60) unless defined $self->{request_timeout};

	return $self
}

# called by framework when a client connects.
# a bunch of the things done in AE::H::HTTPConnection's
# constructor are done here instead (register the "request"
# callback, assign the handle)
sub on_client_connect {
	my $self = shift;

	$self->reg_cb(
		request => sub {
			# stolen from A::HTTPD.pm's new():
			my ($con, $meth, $url, $hdr, $cont) = @_;

			$self->request($con, $meth, $url, $hdr, $cont);
		},

		# ok wow. when AE:H:HTTPConnection is done sending its response,
		# it indirectly triggers a "disconnect" event (via do_disconnect).
		# we need to let our Listener know of the closed connection, so it 
		# can do its own cleanup
        # 20100611 sayulita: this means that anyevent automatically closes
        # each connetion after sending a response
		disconnect => sub {
			my ($self, $err) = @_;

			#Devel::Cycle::find_cycle($self);

			print "in disconnect callback with error '$err'\n";
			$self->{close_callback}->($err);
	
			# AH. this is the proper way to shut down a handle
			# keywords: fh handle connection close
			undef $self->{hdl};
			undef $self->{handle};
		},
	);

	weaken $self;

	# at this point, $self->{handle} has been set to a new AE::Handle object. 
	# AE::HTTPD::HTTPConnection (from which this class descends) expects that
	# as $self->{hdl}. so...
	$self->{hdl} = $self->{handle};

	# when tracking down circular refs, this was needed to avoid a memory leak
	# not sure where the circular ref was. but it's not here exactly.
	# meaning, here, there is no circular ref, but in disconnect handler there is:
	# $Sisyphus::Proto::HTTP::ACTB->{'hdl'} => \%AnyEvent::Handle::ACTH      
	# $AnyEvent::Handle::ACTH->{'on_drain'} => \&ACTI                        
	#         $ACTI variable $self => \$ACTJ                        
	#                        $$ACTJ => \%Sisyphus::Proto::HTTP::ACTB 

	#Devel::Cycle::find_cycle($self);

	weaken $self->{hdl};
	weaken $self->{handle};

	# now, we let AE::HTTPD::HTTPConnection run the show
	$self->push_header_line;
}

# called by framework on client error/disconnect
# we call AE:HTTPD::HTTPConnection's cleanup/close handler
sub on_client_disconnect {
	my $self = shift;
	$self->do_disconnect;
}

sub request {
	# called by A::H::HTTPConnection on request
	# so, we have a full HTTP request, we wish to send it to our application
	my ($self, $con, $meth, $url, $hdr, $cont)  = @_;

	my $req = AnyEvent::HTTPD::Request->new (
		httpd   => $self,
		method  => $meth,
		url     => $url,
		hdr     => $hdr,
		parm    => (ref $cont ? $cont : {}),
		content => (ref $cont ? undef : $cont),
	);

	#Devel::Cycle::find_cycle($req);

	# this is how we get massages back to the application
	$self->{app_callback}->($req);
}

sub frame {
	my ($self, $r) = @_;
	my ($code, $msg, $hdr, $content) = @$r;

#unless (defined ($hdr->{'Content-Length'})) {
#       $hdr->{'Content-Length'} = length($content);
#   }
    # always do connection: close
    $hdr->{'Connection'} = "close";

	$self->response($code, $msg, $hdr, $content);
}
1;
