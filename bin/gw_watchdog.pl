#!/usr/bin/perl

use LoxBerry::System;
use LoxBerry::IO;
use LoxBerry::Log;
use LoxBerry::JSON;
use Getopt::Long;
#use warnings;
#use strict;
#use Data::Dumper;

# Version of this script
my $version = "0.1.0";

# Globals
my $error;
my $verbose;
my $action;

# Logging
my $log = LoxBerry::Log->new (  name => "gw_watchdog",
	package => 'audioserver4home',
	logdir => "$lbplogdir",
	addtime => 1,
);

# Commandline options
GetOptions ('verbose=s' => \$verbose,
            'action=s' => \$action);

# Verbose
if ($verbose) {
        $log->stdout(1);
        $log->loglevel(7);
}

LOGSTART "Starting MQTT-Gateway Watchdog";

# Lock
my $status = LoxBerry::System::lock(lockfile => 'gw-watchdog', wait => 10);
if ($status) {
	LOGCRIT "$status currently running - Quitting.";
	exit (1);
}

# Creating tmp file with failed checks
my $response;
if (!-e "/dev/shm/a4h-gw-watchdog-fails.dat") {
	$response = LoxBerry::System::write_file("/dev/shm/a4h-gw-watchdog-fails.dat", "0");
}

# Todo
if ( $action eq "start" ) {

	&start();

}

elsif ( $action eq "stop" ) {

	&stop();

}

elsif ( $action eq "restart" ) {

	&restart();

}

elsif ( $action eq "check" ) {

	&check();

}

else {

	LOGERR "No valid action specified. --action=start|stop|restart|check is required. Exiting.";
	print "No valid action specified. --action=start|stop|restart|check is required. Exiting.\n";
	exit(1);

}

exit (0);


#############################################################################
# Sub routines
#############################################################################

##
## Start
##
sub start
{

	# Start with:
	if (-e  "$lbpconfigdir/gw_stopped.cfg") {
		unlink("$lbpconfigdir/gw_stopped.cfg");
	}

	my $count = `pgrep -A -c -f "loxaudioserver_mqtt.pl"`;
	chomp ($count);
	if ($count > "0") {
		LOGCRIT "MQTT-Gateway already running. Pleasee stop it before starting again. Exiting.";
		exit (1);
	}

	LOGINF "Starting MQTT-Gateway...";

	#my $output = `perl $lbpbindir/loxaudioserver_mqtt.pl & 2>&1`;
	 system ( "perl $lbpbindir/loxaudioserver_mqtt.pl > /dev/null 2>&1 &");

	my $count = `pgrep -A -c -f "loxaudioserver_mqtt.pl"`;
	chomp ($count);
	if ($count eq "0") {
		LOGCRIT "Could not start MQTT-Gateway - Error: $output";
		exit (1)
	} else {
		my $id = `pgrep -A -f "loxaudioserver_mqtt.pl"`;
		chomp ($id);
		LOGOK "MQTT-Gateway started successfully. PID: $id";
	}

	return (0);

}

sub stop
{

	$response = LoxBerry::System::write_file("$lbpconfigdir/gw_stopped.cfg", "1");

	LOGINF "Stopping MQTT-Gateway...";
	my $output = `pkill -f "loxaudioserver_mqtt.pl" 2>&1`;
	chomp ($output);

	my $count = `pgrep -A -c -f "loxaudioserver_mqtt.pl"`;
	chomp ($count);
	if ($count eq "0") {
		LOGOK "MQTT-Gateway stopped successfully.";
	} else {
		my $id = `pgrep -A -f "loxaudioserver_mqtt.pl"`;
		chomp ($id);
		LOGCRIT "Could not stop MQTT-Gateway - Error: $output. Still Running ID: $id";
		exit (1)
	}

	return(0);

}

sub restart
{

	$log->default;
	LOGINF "Restarting MQTT-Gateway...";
	&stop();
	&start();

	return(0);

}

sub check
{

	LOGINF "Checking Status of MQTT-Gateway...";

	if (-e  "$lbpconfigdir/gw_stopped.cfg") {
		LOGOK "MQTT-Gateway stopped manually. Nothing to do.";
		return(0);
	}

	my $count = `pgrep -A -c -f "loxaudioserver_mqtt.pl"`;
	chomp ($count);
	if ($count eq "0") {
		LOGERR "MQTT-Gateway seems not to be running.";
		my $fails = LoxBerry::System::read_file("/dev/shm/a4h-gw-watchdog-fails.dat");
		chomp ($fails);
		$fails++;
		if ($fails > 9) {
			LOGERR "Too many failures. Will stop watchdogging... Check your configuration and start service manually.";
		} else {
			my $response = LoxBerry::System::write_file("/dev/shm/a4h-gw-watchdog-fails.dat", "$fails");
			&restart();
		}
	} else {
		my $id = `pgrep -A -f "loxaudioserver_mqtt.pl"`;
		chomp ($id);
		LOGOK "MQTT-Gateway is running. Fine. ID: $id";
		my $response = LoxBerry::System::write_file("/dev/shm/a4h-gw-watchdog-fails.dat", "0");
	}

	return(0);

}

##
## Always execute when Script ends
##
END {

	LOGEND "This is the end - My only friend, the end...";
	LoxBerry::System::unlock(lockfile => 'gw-watchdog');

}
