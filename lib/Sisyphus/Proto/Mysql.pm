package Sisyphus::Proto::Mysql;

use Data::Dumper;

# mysql client for sisyphus framework
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Data::Dumper;
use MySQL::Packet qw(:debug);           # dumping packet contents etc.
use MySQL::Packet qw(:test :decode);    # decoding subs
use MySQL::Packet qw(:encode);          # encoding subs
use MySQL::Packet qw(:crypt);          # encoding subs
use MySQL::Packet qw(:COM :CLIENT :SERVER);     # constants
use Data::Hexdumper qw(hexdump);
use Sislog;
use Scalar::Util qw/ weaken /;
use Devel::Cycle;


use constant USE_HANDLE => 1;

sub new {
	my $class = shift;
  	my $in = shift;

	my $self = { };

	$self->{log} = Sislog->new({use_syslog=>1, facility=>"Proto-Mysql"});
	$self->{log}->open();

	$self->{user} = $in->{'user'};
	$self->{pw} = $in->{'pw'};
	$self->{db} = $in->{'db'};
	$self->{on_error} = $in->{'err'};

	# values used by connecttion
	$self->{bytes_wanted} = 0;
	$self->{buffer} = '';

	# these drive the state machine
	$self->{packet} = undef;
	$self->{greeting} = undef;
	$self->{result} = undef;
	$self->{field_end} = undef;

	$self->{handle} = undef;
	$self->{fh} = undef;

	$self->{queryqueue} = [];
	$self->{query_id} = 0;

	return(bless($self, $class));
}

# will get called at connect-time.
# this must eventually call the callback passed to it
sub on_connect {
	my ($self, $cb) = @_;

	weaken $self;

	$self->{connected} = 1;

	# once we're authenticated and ready to use, call this...
	$self->{cb} = sub {
		my $r = shift;

		# it would be nice to be able to detect things like authentication failures here,
		# to be able to alert our calling code via this callback...
		$self->{log}->log("in on_connect callback- i am connected it seems");

		$cb->();
	};

	$self->receive_response_header();
}

sub receive_response_header {
	my $self = shift;

	weaken $self;

	my $handle = $self->{handle};
        #Devel::Cycle::find_cycle($self);

   	my $rc;
   	$self->{packet} = undef;

	$self->{log}->log("in receive_response_header");

   	# four byte header, which include the length of the body    
	$handle->push_read(
		chunk => 4,
		sub {
			my ($handle, $data) = @_;
			# print hexdump($data);
			my $_packet = {};
			$rc = mysql_decode_header $_packet, $data;
			if ($rc < 0) {
				$self->on_error("bad header");
			} elsif ($rc > 0) {
				$self->{packet} = $_packet;
				my $size = $self->{packet}->{packet_size};
				#print STDERR "looks like $size byte packet.\n";
				$self->{log}->log("looks like a $size byte packet");
				$self->receive_response_body();
			}
		}
	);
}

sub receive_response_body {
	my $self = shift;

	weaken $self;

	my $size = $self->{packet}->{packet_size};

	# four byte header, which includes the length of the body	
	$self->{handle}->push_read (
		chunk => $size,
		sub {
			my ($handle, $data) = @_;

			unless ($self->{greeting}) {
				my $rc = mysql_decode_greeting $self->{packet}, $data;
				if ($rc < 0) {
					$self->{on_error}->("strange mysql error"); return;
					$self->service_queryqueue();
				 }
				$self->{greeting} = $self->{packet};
				$self->{packet} = undef;
				my ($h, $p) = $self->create_client_auth();
				$self->send_packet($h, $p);
			} elsif (not $self->{result}) {
				my $rc = mysql_decode_result($self->{packet}, $data);

				if ($rc < 0) {
					$self->{on_error}->("bad result"); return;
					$self->service_queryqueue();
				}

				if ($self->{packet}->{error}) {
					$self->{on_error}->("" .
					  $self->{packet}->{errno} . ": ".
					  $self->{packet}->{message});
					return;
				} elsif ($self->{packet}->{end}) {
					$self->{on_error}->("bad result"); return;
				} else {
					if ($self->{packet}->{field_count}) {
						$self->{result} = $self->{packet};
						$self->receive_response_header();
					} elsif (not $self->{packet}->{server_status} & SERVER_MORE_RESULTS_EXISTS) {
						# that's that..
						#$self->{log}->log("NO_MORE_RESULTS");
						$self->{cb}->(["DONE"]); # jt i think?
						$self->service_queryqueue();
					} else {
						$self->{log}->log("this should be unreachable- error in mysql protocol state");
						$self->service_queryqueue();
					}
				}
			} elsif (not $self->{field_end}) {
				my $rc = do {
					(mysql_test_var $self->{packet}, $data) ? (mysql_decode_field $self->{packet}, $data)
											  : (mysql_decode_result $self->{packet}, $data)
				};
				if ($rc < 0) {
					$self->{on_error}->("bad field packet"); return;
					$self->service_queryqueue();
				} elsif ($rc > 0) {
					#mysql_debug_packet $packet;
					if ($self->{packet}->{error}) {
						$self->{on_error}->("bad credentials?"); return;
						$self->service_queryqueue();
					} elsif ($self->{packet}->{end}) {
						#print STDERR "ok got field_end\n";
						$self->{field_end} = $self->{packet};
						$self->receive_response_header();
					} else {
						#do_something_with_field_metadata($packet);
						#print STDERR "i got field metadata\n";
						#print Dumper $packet;
						$self->receive_response_header();
					}
				}
			} else {
				my $rc = do {
					(mysql_test_var $self->{packet},$data) ? (mysql_decode_row $self->{packet},$data)
												  : (mysql_decode_result $self->{packet},$data)
				};
				if ($rc < 0) {
					$self->{on_error}->("bad row packet"); return;
					$self->service_queryqueue();
				} elsif ($rc > 0) {
					#print "i got a row!!\n";
					#mysql_debug_packet $packet;
					if ($self->{packet}->{error}) {
						die 'the server hates me';
					} elsif ($self->{packet}->{end}) {
						$self->{result} = undef;
						$self->{field_end} = undef;
						unless ($self->{packet}->{server_status} & SERVER_MORE_RESULTS_EXISTS) {
							# that's that..
							# print STDERR "GOT ALL ROWS\n";
							#$self->{log}->log("GOT_ALL_RESULTS");
							$self->{cb}->(["DONE"]);
							$self->service_queryqueue();
						}
					} else {
						# print STDERR "GOT A ROW.\n";
						my @row = @{ $self->{packet}->{row} };
						#print Dumper \@row;
						#$self->{log}->log("GOT_A_ROW");
						$self->{cb}->(\@row);
						$self->receive_response_header();
					}
					$self->{packet} = undef;
				}
			}
		}
	)
}

sub create_client_auth {
    my $self = shift;

    my $flags =  CLIENT_LONG_PASSWORD | CLIENT_LONG_FLAG | CLIENT_PROTOCOL_41 | CLIENT_TRANSACTIONS | CLIENT_SECURE_CONNECTION | CLIENT_CONNECT_WITH_DB;

    my $pw_crypt = mysql_crypt $self->{pw}, $self->{greeting}->{crypt_seed};

    my $packet_body = mysql_encode_client_auth (
        $flags,                                 # $client_flags
        0x01000000,                             # $max_packet_size
        $self->{greeting}->{server_lang},               # $charset_no
        $self->{user},                          # $username
        $pw_crypt,                              # $pw_crypt
        $self->{db},                          # $database
    );

    my $packet_head = mysql_encode_header $packet_body, 1;

    return ($packet_head, $packet_body);
}

sub getQID {
	my $self = shift;
	$self->{qid} += 1;
	return $self->{qid};
}

# note! this is a class method, not an instance method
sub esc {
	my $q = shift;

	# jt 20091012 try escaping terms like this
	$q =~ s/\\/\\\\/sg;
	$q =~ s/\000/\\0/sg;
	$q =~ s/\'/\\'/sg;
	$q =~ s/\"/\\"/sg;
	$q =~ s/\010/\\b/sg;
	$q =~ s/\n/\\n/sg;
	$q =~ s/\r/\\r/sg;
	$q =~ s/\t/\\t/sg;
	$q =~ s/\Z/\\Z/sg;
	
	return $q;
}

sub query {
	my $self = shift;
	my $args = { @_ };

	my $q = $args->{q};
	my $cb = $args->{cb};

	my $packet_body = mysql_encode_com_query $q;
	my $packet_head = mysql_encode_header $packet_body;

	$self->{log}->log("in query, in_q is $self->{in_q}");

	push(@{$self->{queryqueue}}, {
		cb => $args->{cb},
		cqid => $args->{cqid},
		body => $packet_body,
		head => $packet_head,
	});
	#print Dumper $self->{queryqueue};

	unless ($self->{in_q}) { $self->service_queryqueue(); }
}

sub service_queryqueue {
	my $self = shift;

	$self->{log}->log("servicing queryqueue");
	my $item = pop(@{$self->{queryqueue}});
	my $cb = $item->{cb};

	if ($item->{head}) {
		$self->{in_q} = 1;
		$self->{cqid} = $item->{cqid};
		$self->{cb} = $cb;

		$self->{log}->log("popped item from query queue, sending to mysql");

		# send actual query packets to mysql server
		$self->send_packet($item->{head}, $item->{body});
	} else {
		$self->{in_q} = undef;
		$self->{log}->log("query queue empty, in_q set to undef");
	}
}

sub send_packet {
    my ($self, $h, $b) = @_;

	#print "h:\n";
	#print hexdump($h);
	#print "b:\n";
	#print hexdump($b);

    $self->{handle}->push_write($h);
    $self->{handle}->push_write($b);

    $self->receive_response_header();
}



1;

