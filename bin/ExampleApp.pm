package ExampleApp;

# this is an example HTPPAppServer app
# methods named METHOD_* will be exposed in the app server

print "ExampleApp LOADED!!\n";

sub METHOD_hello {
	my $req = shift;
	print "in ExampleApp::hello with $req\n";

}

1;
