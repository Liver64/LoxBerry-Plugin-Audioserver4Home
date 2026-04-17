#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use CGI;
use JSON;

my $error;
my $response;
my $cgi = CGI->new;
my $q = $cgi->Vars;

if( $q->{action} eq "asservicerestart" ) {
	system ("$lbpbindir/as_watchdog.pl --action=restart --verbose=0 > /dev/null 2>&1 &");
	my $resp = $?;
	sleep(1);
	my $status = LoxBerry::System::lock(lockfile => 'as-watchdog', wait => 600);
	$response = $resp;
}

if( $q->{action} eq "asservicestop" ) {
	system ("$lbpbindir/as_watchdog.pl --action=stop --verbose=0 > /dev/null 2>&1");
	$response = $?;
}

if( $q->{action} eq "asservicestatus" ) {
	my $id;
	my $count = `sudo docker ps | grep -c Up.*lox-audioserver`;
	if ($count >= "1") {
		$id = `sudo docker ps | grep Up.*lox-audioserver | awk '{ print \$1 }'`;
		chomp ($id);
	}
	my %response = ( pid => $id );
	chomp (%response);
	$response = encode_json( \%response );
}

if( $q->{action} eq "getconfig" ) {
	require LoxBerry::JSON;
	my $cfgfile = "$lbpconfigdir/plugin.json";
	my $jsonobj = LoxBerry::JSON->new();
	my $cfg = $jsonobj->open(filename => $cfgfile, readonly => 1);
	$response = encode_json( $cfg );
}

if( $q->{action} eq "getzones" ) {
	my $shm_file = '/dev/shm/audioserver4home.json';
	if ( open(my $fh, '<:utf8', $shm_file) ) {
		local $/;
		$response = <$fh>;
		close $fh;
	} else {
		$error = "Zone data not available ($shm_file): $!";
	}
}

if( defined $response and !defined $error ) {
	print "Status: 200 OK\r\n";
	print "Content-type: application/json; charset=utf-8\r\n\r\n";
	print $response;
}
elsif ( defined $error and $error ne "" ) {
	print "Status: 500 Internal Server Error\r\n";
	print "Content-type: application/json; charset=utf-8\r\n\r\n";
	print to_json( { error => $error } );
}
else {
	print "Status: 501 Not implemented\r\n";
	print "Content-type: application/json; charset=utf-8\r\n\r\n";
	print to_json( { error => "Action " . $q->{action} . " unknown" } );
}
