package PCREHTTPD;

# this is a Sisyphus Application.
# An HTTPD where url->method routing is taken care of by a config file
# that is simply a regular expression, which maps URLs to methods

use strict;
use base 'Sisyphus::Application';

use Data::Dumper;
use IO::AIO;
use AnyEvent::AIO;
use Fcntl;

use constant INTERNAL_LOG => 1;
use constant APP_LOG => 2;

use Time::HiRes;

my $responses;


sub new {
	my $class = shift;
	my $mod = shift;
	my $re = shift;

	my $self = { };

	$self->{re} = $re;
	$self->{mod} = $mod;

    require $mod. ".pm";

	bless($self, $class);
	$self->open_logs();

	return($self);
}

sub open_logs {
	my $self = shift;

	my $cv = AnyEvent->condvar;
	aio_open "/tmp/pcrehttp_log", O_WRONLY|O_CREAT|O_APPEND, 0666, sub {
		$self->{httplog_fh} = $_[0];
		$cv->send();
	};
	$cv->recv;

	my $cv = AnyEvent->condvar;
	aio_open "/tmp/pcrehttp_app_log", O_WRONLY|O_CREAT|O_APPEND, 0666, sub {
		$self->{applog_fh} = $_[0];
		$cv->send();
	};
	$cv->recv;

	print "logs open\n";
}

sub new_connection {
	my $self = shift;
	print  "new connection\n";
}

sub remote_closed {
	my ($self, $host, $port, $fh) = @_;
	delete $responses->{$fh};
}

sub message {
	my ($self, $host, $port, $dat, $fh) = @_;

	my $req = $dat->[0];

    # $req is an AE::HTTPD::Request instance
    # Request class has methods for talking to the AE loop
    # but we'll do it by hand here to demonstrate the use of Sisyphus
    my $meth = $req->method();
    my $url= $req->url;
    my $params = $req->vars();
    my $headers = $req->headers();

	my $f;
	foreach my $r (@{$self->{re}}) {
		if ($url->as_string() =~ /$r->[0]/) {
			$f = $r->[1];
			last;
		}
	}
	unless ($f) {
			my $cont = "404 notfound bro";
			$self->logthis($fh, INTERNAL_LOG, "$host $meth " . $url->as_string() . " -> ?? 404 " . length($cont));
			$responses->{$fh} =
				[404, "NOT_FOUND", {"Content-type" => "text/html",}, $cont];
			$self->{client_callback}->([$fh]);	
	} else {

		my $m = $self->{mod} . "::" . $f;

		if (defined &{$m}) {
			my ($code, $str, $headers, $cont);
			# haha. getting around strict refs. see http://perldoc.perl.org/strict.html
			my $bar = \&{$m};
			eval {
				$bar->($meth, $url, $params, $headers, sub {

					# callback from our app to the user
					($code, $str, $headers, $cont) = @_;	
					$responses->{$fh} = [$code, $str, $headers, $cont];
					$self->{client_callback}->([$fh]);	

				}, sub {
					# logging callback for our app
					my $dat = shift;
					$self->logthis($fh, APP_LOG, "$dat");
				});
			};

			if ($! or $@) {
				# error. death.
				my $errm = $!;
				undef $!; undef $@;
				$cont = "Alas. It seems as though we found a server error.";
				$responses->{$fh} =
					[500, "ERROR", {"Content-type" => "text/html",}, $cont];
				$self->logthis($fh, INTERNAL_LOG, "$host $meth " . $url->as_string() . " -> $m 500 " . length($cont));
				#$self->logthis($fh, INTERNAL_LOG, "eerrr");
				$self->{client_callback}->([$fh]);	
			} else {
				# woo. a message from our application	
				$self->logthis($fh, INTERNAL_LOG, "$host $meth " . $url->as_string() . " -> $m $code " . length($cont));
			}

		} else {
			my $cont = "404 notfound bro";
			$self->logthis($fh, INTERNAL_LOG, "$host $meth " . $url->as_string() . " -> ??? 404 " . length($cont));
			$responses->{$fh} =
				[404, "NOT_FOUND", {"Content-type" => "text/html",}, $cont];
			$self->{client_callback}->([$fh]);	
		}

		return undef;
	}
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

sub logthis {
	my ($self, $fh, $which, $dat) = @_;

	my ($sec, $usec) = Time::HiRes::gettimeofday();
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($sec);
	$mon += 1; $year += 1900;
	my $time = "$year/$mon/$mday $hour:$min:$sec.$usec";

	if ($which == INTERNAL_LOG) {
		aio_write $self->{httplog_fh}, undef, undef, "$fh $time $dat\n", undef, sub {;};
	} elsif ($which == APP_LOG) {
		aio_write $self->{applog_fh}, undef, undef, "$fh $time $dat\n", undef, sub {;};
	} else {
		aio_write $self->{applog_fh}, undef, undef, "$fh $time $dat\n", undef, sub {;};
	}
}

1;
