package Sislog;

# simple AnyEvent/AIO logger, part of Sisyphus

use strict;
use AnyEvent;
use IO::AIO;
use AnyEvent::AIO;
use Fcntl;

sub new {
	my $class = shift;

	my $self = {
		fn => undef,
		fh => undef,
		in_write => undef,
	};

	bless($self, $class);
	return($self);
}

# synchronous! watch out.
sub open {
	my $self = shift;

	print "trying to open " . $self->{fn} . "\n";
	
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

    my ($sec, $usec) = Time::HiRes::gettimeofday();
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($sec);
    $mon += 1; $year += 1900;
    my $time = "$year/$mon/$mday $hour:$min:$sec.$usec";

	$self->{wbuf} .= "$id $time $dat\n";

	unless($self->{in_write}) { $self->service(); } else { print "already in write\n"; }
}

sub service {
	my $self = shift;

	if (length($self->{wbuf})) {
		$self->{in_write} = 1;
		aio_write $self->{fh}, undef, undef, $self->{wbuf}, undef, sub {
			my $len = $_[0];
			if ($len > 0) {
				$self->{wbuf}= substr $self->{wbuf}, $len;
				$self->service();
			} else {
				# jeez. an error writing out log. clear the buffer so we don't
				# just fill memory forever, maybe print something?
				$self->{wbuf} = '';
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
