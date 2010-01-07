package ExampleJSONApplication;

use strict;

# implements a trivial little echo server

my $request_count = 0;

sub new {
	my $class = shift;
	my $self = { };

	return(bless($self, $class));
}

sub new_connection {
	my ($self, $host, $port, $cid) = @_;

	$self->{responses}->{$cid} = [];
}

sub remote_closed {
	my ($self, $host, $port, $cid) = @_;

	delete $self->{responses}->{$cid};
}

sub message {
	my ($self, $host, $port, $message, $cid, $stash) = @_;

	$request_count += 1;

	my $obj = $message->[0];	
	my $body = $obj->{'body'};

	if ($obj->{set_message}) {
		$stash->{outgoing_message} = $obj->{body};
	}

	my $response = {
		request_number => $request_count,
		body => scalar reverse $body,
	};
	
	push(@{$self->{responses}->{$cid}}, $response);
	$self->{client_callback}->([$cid]);	
}

sub get_data {
	my ($self, $cid) = @_;
	
	return(pop(@{$self->{responses}->{$cid}}));
}

1;
