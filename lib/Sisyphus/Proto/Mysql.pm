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

use constant USE_HANDLE => 1;

sub new {
	my $class = shift;
  	my $in = shift;

	my $self = { };

	$self->{log} = Sislog->new({use_syslog=>1, facility=>"Proto::Mysql"});
	$self->{log}->open();
	$self->{log}->log("instantiating mysql object");

	#unless ($self->{port}) { $self->{port} = 3306; }
	#unless ($self->{host}) { $self->{host} = "localhost"; }

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

	$self->{query_queue} = [];
	$self->{query_id} = 0;


	return(bless($self, $class));
}

# will get called at connect-time.
# this must eventually call the callback passed to it
sub on_connect {
	my $self = shift;
	my $cb = shift;

	$self->{connected} = 1;

	# once we're authenticated and ready to use, call this...
	$self->{cb} = $cb;

	$self->{log}->log("on_connect");

	$self->receive_response_header();
}

sub receive_response_header {
	my $self = shift;

	my $handle = $self->{handle};

   	my $rc;
   	$self->{packet} = undef;

	# print STDERR "in receive response header\n";

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
				$self->receive_response_body();
			}
		}
	);
}

sub receive_response_body {
	my $self = shift;

	my $size = $self->{packet}->{packet_size};
	# print STDERR "in receive body. size $size\n";

	# four byte header, which include the length of the body	
	$self->{handle}->push_read (
		chunk => $size,
		sub {
			my ($handle, $data) = @_;
			#print hexdump($data);
			unless ($self->{greeting}) {
				#my ($handle, $data) = @_;
				#print STDERR "GREETING.\n";
				my $rc = mysql_decode_greeting $self->{packet}, $data;
				if ($rc < 0) {
					$self->{on_error}->("strange mysql error"); return;
					$self->service_queryqueue();
				 }
				$self->{greeting} = $self->{packet};
				#mysql_debug_packet($self->{greeting});
				$self->{packet} = undef;
				my ($h, $p) = $self->create_client_auth();
				$self->send_packet($h, $p);
			} elsif (not $self->{result}) {
				#print STDERR "RESULT.\n";
				my $rc = mysql_decode_result($self->{packet}, $data);

				if ($rc < 0) {
					$self->{on_error}->("bad result"); return;
					$self->service_queryqueue();
				}

				# mysql_debug_packet $self->{packet};

				if ($self->{packet}->{error}) {
					$self->{on_error}->("" .
					  $self->{packet}->{errno} . ": ".
					  $self->{packet}->{message});
					return;
				} elsif ($self->{packet}->{end}) {
					$self->{on_error}->("bad result"); return;
				} else {
					if ($self->{packet}->{field_count}) {
						#print STDERR "looks like i got a field count.\n";
						$self->{result} = $self->{packet};
						# fields and rows to come
						$self->receive_response_header();
					} elsif (not $self->{packet}->{server_status} & SERVER_MORE_RESULTS_EXISTS) {
						# that's that..
						#print STDERR "i want to be done, i think\n";
						$self->{cb}->(undef); # jt i think?
						$self->service_queryqueue();
					} else {
						#print STDERR "i don't know what i'm doing here...\n";
						$self->service_queryqueue();
					}
				}
			} elsif (not $self->{field_end}) {
				# print "ok in NO_FIELD_END\n";
				my $rc = do {
					(mysql_test_var $self->{packet}, $data) ? (mysql_decode_field $self->{packet}, $data)
											  : (mysql_decode_result $self->{packet}, $data)
				};
				#print "rc is $rc\n";
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
							$self->{cb}->(undef);
							$self->service_queryqueue();
						}
					} else {
						# print STDERR "GOT A ROW.\n";
						my @row = @{ $self->{packet}->{row} };
						#print Dumper \@row;
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

    return ($packet_head,$packet_body);
}

sub getQID {
	my $self = shift;
	$self->{qid} += 1;
	return $self->{qid};
}

sub query {
    my $self = shift;
    my $args = { @_ };

    my $q = $args->{q};

    my $packet_body = mysql_encode_com_query $q;
    my $packet_head = mysql_encode_header $packet_body;

	# print "pushing client qid $cqid on the query queue\n";
    push(@{$self->{queryqueue}}, {
		cb => $args->{cb},
		cqid => $args->{cqid},
		body => $packet_body,
		head => $packet_head,
	});

	unless ($self->{in_q}) { $self->service_queryqueue(); }
}

sub service_queryqueue {
	my $self = shift;

	#print "servicing query queue\n";
	my $item = pop(@{$self->{queryqueue}});

	if ($item) {
		$self->{in_q} = 1;
		$self->{cqid} = $item->{cqid};
    	$self->{cb} = $item->{cb};

		# send actual query packets to mysql server
	    $self->send_packet($item->{head}, $item->{body});
	} else {
		$self->{in_q} = undef;
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

