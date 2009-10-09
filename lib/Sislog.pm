package Sislog;

# simple AnyEvent/AIO logger, part of Sisyphus
# can also speak to syslog
# also, we grab STDERR and STDOUT. which should be configuarable.

use strict;
use AnyEvent;
use IO::AIO;
use AnyEvent::AIO;
use Fcntl;
use Log::Syslog::Fast ':all';
use Sys::Hostname;

# tie me up
#tie(*STDOUT, 'Sislog', { facility => "stdout", use_syslog => 1, }); 
#tie(*STDERR, 'Sislog', { facility => "stderr", use_syslog => 1, }); 

my @wbuf;

sub new {
	my $class = shift;
	my $in = shift;

 	my $facility =  $in->{facility} || "SET_FACILITY_IN_SISLOG_OBJECT";
	my $use_syslog = $in->{use_syslog};
	
	my $self = {
		use_syslog => $in->{use_syslog},
		facility => $facility,
		fn => undef,
		fh => undef,
		in_write => undef,
		opened => undef,
	};

	bless($self, $class);
	return($self);
}

# for tied things...
sub TIEHANDLE {
	my ($class, $params) = @_;
	my $self = Sislog->new($params);
	$self->open();
}

sub PRINT {
	my $self = shift;
	my $dat = shift;
	$self->log($dat);
}

# synchronous! watch out.
sub open {
	my $self = shift;

	if ($self->{use_syslog}) {
		$self->{syslog} = Log::Syslog::Fast->new(
			LOG_UDP,
			"127.0.01",
			514,
			LOG_LOCAL2,
			LOG_INFO,
			Sys::Hostname::hostname,
			$self->{facility});
		return;
	}

	my $cv = AnyEvent->condvar;
	aio_open $self->{fn}, O_WRONLY|O_CREAT|O_APPEND, 0666, sub {
		$self->{fh} = $_[0];
		unless ($self->{fh}) { print STDERR "error opening log file $self->{fn}\n"; }
		$cv->send();
	};

	$cv->recv;
}

sub log {
	my ($self, $id, $dat) = @_;

	unless ($self->{opened}) { $self->open() };

	if ($self->{use_syslog}) {
		$self->{syslog}->send("$id $dat", time);
		return;
	}

	my ($sec, $usec) = Time::HiRes::gettimeofday();
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($sec);
	$mon += 1; $year += 1900;
	my $time = "$year/$mon/$mday $hour:$min:$sec.$usec";

	my $line = "$id $time $dat\n";
	push @wbuf, $line;

	unless($self->{in_write}) { $self->service(); }
}

sub service {
	my $self = shift;

	if (scalar(@wbuf)) {
		$self->{in_write} = 1;
		my $line = shift @wbuf;
		aio_write $self->{fh}, undef, length($line), $line, undef, sub {
			my $len = $_[0];
			if ($len > 0) {
				$self->service();
			} else {
				# jeez. an error writing out log. clear the buffer so we don't
				# just fill memory forever, maybe print something?
				@wbuf = [];
				print STDERR "logging error! aio_write returned error $!\n";
			}
		}
	} else {
		$self->{in_write} = undef;
	}
}

sub rotate {
	# implement me, please

}

1;
