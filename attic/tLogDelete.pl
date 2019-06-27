#!/usr/bin/perl
use strict;
use warnings;
use File::Tail;
use Data::Dumper;
use Storable qw(nstore retrieve);

my $debug = 1;

my $trConnect = "transmission-remote 127.0.0.1";

# time in which the main cacheDB is refreshed
my $cacheTime = 500;

# cache file storage
my $storeFile = '/tmp/td.data';

# log file for transmission
my $transmissionLogFile = "/var/log/transmission/transmission.log";

if ($debug) {
	print "tLogDelete starting up...\n";
	print "fetching cacheDB\n";
}

## since we just started lets get a fresh copy of the cacheDB
our $cacheDB = ();
getCacheDB();

if ($debug) {
	print "logger starting...\n";
}

# open the log file and parse it out
my $file = File::Tail->new($transmissionLogFile);
my $logBatch = 0;
while ( defined( my $line = $file->read ) ) {
	if ($debug) {
		print "[LOG READ]: $logBatch | [TOTAL DELETED]: $cacheDB->{'deletedCount'}\n";
		if ($cacheDB->{'retry'}) { print "[cacheDB](WARNING): in retry\n"; }
	}

	# read each line and find Unregistered and store the id and name.
	if ( $line =~ /.*\]\s(.*)\sUnregistered\storrent\s\(announcer.c..*/ ) {

		# get latest cacheDB if needed
		getCacheDB();

		# found
    if ($debug) { print "Transmission Log [Unregistered]: $1\n"; }

		# check the cachedb and only process ones we have IDs for.
    if ($cacheDB->{'list'}->{$1}->{'id'}) {
			my $tid = $cacheDB->{'list'}->{$1}->{'id'};
			# if it was already deleted skip it
			if (!$cacheDB->{'list'}->{$tid}->{'deleted'}) {
	    	deleteT($tid);
			} else {
				print "skipping $1 already deleted\n";
			}
	  } else {
	  	print "can't find $1 's ID\n";
		}
	# update the log batch counter since we found one.
	$logBatch++;
	}
}

# all done exit
exit;
## functions
# determines if we need to get a cached copy or a new transmission pull
sub getCacheDB {

	# check for cache file newer CACHETIME seconds ago
	if ((-f $storeFile && time - ( stat($storeFile) )[9] < $cacheTime )) {
		# use cached data
		$cacheDB = retrieve($storeFile);
		return $cacheDB;
	} else {
		$cacheDB->{'retry'} = 1;
	}

	# check that we are not in retry
	while ($cacheDB->{'retry'}) {
		# grab the status URL (fresh data)
		if ($debug) { print "refreshing cache\n"; }
		updateList();
		if (!$cacheDB->{'retry'}) {
			nstore( $cacheDB, $storeFile );
			return $cacheDB;
		}
		if ($debug) { print "failed to referesh sleeping 30 seconds\n"; }
		# sleep 30 seconds
		sleep 30;
	}

}

# updateLists gets the latests torrents and stores them
sub updateList {
	if (!$cacheDB->{'deletedCount'}) {
		$cacheDB->{'deletedCount'} = 0;
	}
	$cacheDB->{'count'} = 0;
	if ($debug) { print "updatingList\n"; }

  # open transmission handler
  open( LINE, "$trConnect -l|" );
  while (my $listLine = <LINE>) {
    if ($listLine =~ /\s*(\d+)\**\s.*(Idle|Seeding|Downloading|Paused|Stopped)\s+(.*)$/) {
      if ($debug) { print "found id: $1 | name: $3\n"; }
			$cacheDB->{'count'}++;
      $cacheDB->{'list'}->{$3}->{'id'}   = $1;
      $cacheDB->{'list'}->{$1}->{'name'} = $3;
    }

		if ($listLine =~ /.*Timeout was reached.*/) {
			$cacheDB->{'retry'} = 1;
			return;
		}
  }    # end while
  close(LINE);

	if ($cacheDB->{'count'} > 1) {
		# reset the log batch counter
    $logBatch=0;

		# update our cacheDB age
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    $cacheDB->{'age'} = sprintf ( "%04d%02d%02d%02d:%02d:%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec);
		if ($debug) { print "finished updatingList\n"; }

		# notify jackBot
    return;
	} else {
		if ($debug) { print "connection to transmission failed\n"; }
		$cacheDB->{'retry'} = 1;
		return;
	}
}

# sends delete command to tranmission
sub deleteT {
  my($id) = @_;

  # execute the delete
  my $delT = `$trConnect -t $id --remove-and-delete`;

  # responded: "success"
  if ($delT =~ /.*responded: "success".*/) {
		if ($debug) { print "success\n"; }
		$cacheDB->{'list'}->{$id}->{'deleted'} = 1;
		$cacheDB->{'deletedCount'}++;
	} else {
		if ($debug) { print "delete failed will retry\n"; }
		$cacheDB->{'list'}->{$id}->{'deleted'} = 0;
  }
  # we should add a sleep because we don't want to kill transmission
  sleep(2);
}
