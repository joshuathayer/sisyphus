package ExamplePCREApp;

# this is an example PCREHTTPD app

print "ExamplePCREApp LOADED!!\n";

sub index {
	my ($meth, $u, $params, $cont, $cb, $logcb) = @_;

	$cb->(200, "OK", {"content-type" => "text/html"},
	                  "<html><head><title>it worked</title></head><body><h4>it worked hooray</h4></body></html>"
	);
}

sub test {
	my ($meth, $u, $params, $cont, $cb, $logcb) = @_;

	$logcb->("log test in test function");

	$cb->(200, "OK", {"content-type" => "text/html"},
	                  "<html><head><title>HAHA TEST</title></head><body>keep killing them regularly!</body></html>"
	);
}

sub dienow {
	my ($meth, $u, $params, $cont, $cb, $logcb) = @_;

	$logcb->("going to try dying");

	die;
}

1;
