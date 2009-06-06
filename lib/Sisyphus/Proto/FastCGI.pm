package anyfcgid;

# this won't work yet in the sisyphus work. just getting code in the right places

use AnyEvent::Socket;
use strict;
use Data::Dumper;

my $clients;
my $handler_class;

use constant FCGI_BEGIN_REQUEST      => 1;
use constant FCGI_ABORT_REQUEST      => 2;
use constant FCGI_END_REQUEST        => 3;
use constant FCGI_PARAMS             => 4;
use constant FCGI_STDIN              => 5;
use constant FCGI_STDOUT             => 6;
use constant FCGI_STDERR             => 7;
use constant FCGI_DATA               => 8;
use constant FCGI_GET_VALUES         => 9;
use constant FCGI_GET_VALUES_RESULT  => 10;

use constant FCGI_RESPONDER  => 1;
use constant FCGI_AUTHORIZER => 2;
use constant FCGI_FILTER     => 3;

use constant FCGI_REQUEST_COMPLETE =>  0;
use constant FCGI_CANT_MPX_CONN  =>  1;
use constant FCGI_OVERLOADED     =>  2;
use constant FCGI_UNKNOWN_ROLE   =>  3;


my $tmap = {
	1  => 'FCGI_BEGIN_REQUEST',
	2  => 'FCGI_ABORT_REQUEST',
	3  => 'FCGI_END_REQUEST',
	4  => 'FCGI_PARAMS',
	5  => 'FCGI_STDIN',
	6  => 'FCGI_STDOUT',
	7  => 'FCGI_STDERR',
	8  => 'FCGI_DATA',
	9  => 'FCGI_GET_VALUES',
	10  => 'FCGI_GET_VALUES_RESULT',
	11  => 'FCGI_UNKNOWN_TYPE',
};

my $rolemap = {
	1 => 'FCGI_RESPONDER',
	2 => 'FCGI_AUTHORIZER',
	3 => 'FCGI_FILTER',
};

my $rmap;
foreach my $k (keys(%$tmap)) {
	$rmap->{ $tmap->{$k} } = $k;
}

my $rrmap;
foreach my $k (keys(%$rolemap)) {
	$rrmap->{ $rolemap->{$k} } = $k;
}

my $reqcount = 0;
my $liveconn = 0;

# a simple tcp server
sub run {
	my $p = { @_ };
	$handler_class = $p->{handler_class};

	tcp_server undef, 8888, sub {
		my ($fh, $host, $port) = @_;
	
		$liveconn += 1;
		print STDERR "accept.\n";
	
		my $read_watcher;
		$read_watcher = AnyEvent->io(
			fh => $fh,
			poll => "r",
			cb => sub {
				my $in;
				unless (defined($in)) { $in = ''; }
	
				unless($clients->{$fh}) {
					$clients->{$fh}->{state} = "HEADER";
					$clients->{$fh}->{new} = 1;
					$clients->{$fh}->{bytes_wanted} = 8;
					$clients->{$fh}->{buffer} = "";
				}
	
				my $len = sysread $fh, $in,
					$clients->{$fh}->{bytes_wanted}, length $in;
	
				$clients->{$fh}->{buffer} .= $in;
	
				#print "got $len bytes:\n";
				#hexdump($in);
				#print "\n";
	
				if ($len == 0) {
					# zero-length read means socket closed, right?
					# seems weird that fcgi should close the socket
					remote_closed($fh, $clients->{$fh});
					#print Dumper $clients->{$fh};
					print "CLOSING connection for client(s) " . 
					join " ", (keys(%{$clients->{$fh}->{reqs}})) ;
					print "\n\n";
					delete $clients->{$fh};
					close $fh;
					undef $read_watcher;
					$liveconn -= 1;
				} elsif ($len > 0) {
					# handle() will return a request object
					# when there is one to work on.
					my $rid = handle($clients->{$fh});
					if ($rid) {
						request($fh, $clients->{$fh}->{reqs}->{$rid});
					}
				} else {
					print STDERR "ERROR ON SOCKET.\n";
					print "ERROR ON SOCKET.\n";
					delete $clients->{$fh};
					close $fh;
					undef $read_watcher;
					$liveconn -= 1;
				}
	
				# woah. perl hack: reference the callback within
				# the callback, so it won't get cleaned up after running
				if (0) {
					undef $read_watcher;
				}
			},
		);
	
	}, sub {
		my ($fh, $thishost, $thisport) = @_;
		warn "bound to $thishost, port $thisport\n";
	};

	AnyEvent->condvar->recv;
}
	
sub frame {
	my ($fh, $type, $rid, $body) = @_;

	my $length = length($body);

	my $v = 1;
	my $l0 = int($length / 256);
	my $l1 = int($length % 256);
	my $rid0 = int($rid / 256);
	my $rid1 = int($rid % 256);
	my $pl = 0;
	my $h = pack("C8", $v, $type, $rid0, $rid1, $l0, $l1, $pl, 0);
	$h =$h . $body;

	my $s = syswrite $fh, $h;

	print "SENT request ID $rid, $s bytes\n";
}

# for every full request, this gets fired off
# parse request into shit
# tie in outside handler here
sub request {
	my ($fh, $r) = @_;

	$r->{fh} = $fh;
	$r->{cb} = \&return_request;
	$handler_class->handle($r);

}

sub return_request {
	my $r = shift;

	my $fh = $r->{req}->{fh};
	my $result_code = $r->{result_code};
	my $result_data = $r->{result_data};

	frame($fh, FCGI_STDOUT, $r->{req}->{rid}, $r->{result_data});

	$reqcount += 1;

	my $h = pack("C8", 0, 0, 0, 0, FCGI_REQUEST_COMPLETE, 0, 0, 0);
	frame($fh, FCGI_END_REQUEST, $r->{req}->{rid}, $h);
}

sub remote_closed {
	my ($fh, $c) = @_;

#	print "remote closed!\n";
}

sub handle {
	my $c = shift;
	if ($c->{state} eq "HEADER") {
		# we got a full header

		my ($v, $t, $rid0, $rid1,
		    $l0, $l1, $pl, undef) =
		    unpack("C8",$c->{buffer});

		my $rid = ($rid0 * 256) + $rid1;
		my $length = ($l0 * 256) + $l1;

		if ($c->{new}) {
			$c->{new} = 0;
			print "OPENING connection for request ID $rid\n";
		} else {
			print "AN EXISTING connection for request ID $rid\n";
		}

		print "request type $tmap->{$t}, ";
		print "want $length bytes\n";

		$c->{bytes_wanted} = $length;
		$c->{buffer} = '';
		$c->{state} = "PAYLOAD";
		$c->{request_id} = $rid;
		$c->{reqs}->{$rid}->{type}=$t;
		$c->{reqs}->{$rid}->{rid}=$rid;

		# if we have a state where bytes_wated == 0,
		# we'll recursively call handle(), so the code 
		# below gets a chance to run. 
		if ($c->{bytes_wanted} == 0) {
			return handle($c);
		}

	} elsif ($c->{state} eq "PAYLOAD") {
		# we got a full payload
		
		if ($c->{reqs}->{ $c->{request_id} }->{type} == FCGI_BEGIN_REQUEST) {
			my ($r0, $r1, $f, undef) =
			    unpack("C8",$c->{buffer});
			my $role = ($r0 * 256) + $r1;

			print "role is $rolemap->{$role}\n";
			# XXX ignoring flags...

			# reset buffers for this request_id
			$c->{reqs}->{ $c->{request_id} }->{params} = {};
			$c->{reqs}->{ $c->{request_id} }->{stdin} = '';
		}

		if ($c->{reqs}->{ $c->{request_id} }->{type} == FCGI_PARAMS) {
			unless(length($c->{buffer})) {

				# print "ended cgi params.\n";

				my $b = $c->{reqs}->{ $c->{request_id} }->{param_buffer};
				my $on = 0;
				while($on < length($b)) {
					my ($l0, $l1) = unpack("C2", substr($b, $on, 2));
					$on += 2;
					my $k = substr($b, $on, $l0);
					$on += $l0;
					my $v = substr($b, $on, $l1);
					$on += $l1;
					#print "$k: $v\n";

					# XXX
					# in the case of multiple params, the
					# last one over the wire will be the value
					# the applcation sees. this isn't to spec.
					$c->{reqs}->{ $c->{request_id} }->{params}->{$k}=$v;
				}

				my $clength = $c->{reqs}->{ $c->{request_id} }->{params}->{CONTENT_LENGTH};
				if ($clength) {
					#print "think we'll have a stdin or so.\n";
					$c->{bytes_wanted} = $clength;
				}
			}

			$c->{reqs}->{ $c->{request_id} }->{param_buffer} .= $c->{buffer};
			$c->{buffer} = '';
		}

		if ($c->{reqs}->{ $c->{request_id} }->{type} == FCGI_STDIN) {
			unless(length($c->{buffer})) {
				# print "ended cgi stdin:\n";
				# print $c->{reqs}->{ $c->{request_id} }->{stdin} . "\n";

				# we are good to handle the request now
				$c->{bytes_wanted} = 8;
				$c->{buffer} = '';
				$c->{state} = "HEADER";
				return($c->{request_id});

			} else {
				$c->{reqs}->{ $c->{request_id} }->{stdin} .= $c->{buffer};
			}
		}

		$c->{bytes_wanted} = 8;
		$c->{buffer} = '';
		$c->{state} = "HEADER";
		$c->{reqs}->{ $c->{request_id } }->{type} = undef;
		$c->{request_id} = undef;

	}
}

sub hexdump {
	my $in = shift;

	foreach (split('', $in)) {
		my $o = ord($_);
		if (($o > 32) and ($o < 134)) {
			print " $_ ";
		} else {
			printf "%2.2x ", $o;
		}
	}
	print "\n";
}


1;
