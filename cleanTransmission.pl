#!/usr/bin/env perl

use strict;
use warnings;
use FindBin qw($Bin $Script);
use lib "$Bin/../lib";
use POSIX qw(strftime);
use Log::Log4perl;
use JSON;
use Mojo::Transmission;
use Config::Simple;

# load the logger
Log::Log4perl->init("$Bin/log.conf");

my $log = Log::Log4perl->get_logger('transmissionCleaner');

my $masterList = runTransmissionSync();

# you can output the master list if you want

exit;

# run the sync
sub runTransmissionSync {
  my $file = "$Bin/settings.conf";
  my $cfg = new Config::Simple($file);
  my @clients = $cfg->param("system.clients");

  $log->info("starting transmission updater");
  # cycle though logs
  my $clientCount = @clients;
  my $totalTrCount = 0;
  if ($clientCount) {
    my $torrents = ();
    foreach my $client (@clients) {
      $log->info("updating $client downloader");
      # load the config
      my $config = getTransmissionConfig($client);

      # fetch the latest data from the client
      my $data = fetchTorrents($client);

      $log->info("fetched $data->{'stats'}->{'total'}");
      $totalTrCount += $data->{'stats'}->{'total'};

      unless ($data) {
        $log->error('unable to fetch data');
        next;
      }

      # store it in the global hash
      $torrents->{$client} = $data;
    }
    $log->info("sync completed with $totalTrCount total");
    return $torrents;
  }
}

# load the config
sub getTransmissionConfig {
  my $downloader = shift;
  my $file = "$Bin/settings.conf";
  my $cfg = new Config::Simple($file);
  my $config = $cfg->get_block($downloader);
  return $config;
}

# fetch all the latests data from transmission via RPC
sub fetchTorrents {
  my $downloader = shift;
  my $config = getTransmissionConfig($downloader);

  my $host = $config->{'host'};
  my $port = $config->{'port'};

  # fields
  my $url = "http://$host:$port/transmission/rpc";
  $log->debug("loading rpc data from $url");

  my $tClient = Mojo::Transmission->new;
  $tClient->url($url);
  my $jsonData = $tClient->torrent(['id','name','status','rateUpload','rateDownload','uploadedEver','uploadRatio','trackerStats','sizeWhenDone','error','errorString','eta','percentDone','peersConnected','peersSendingToUs','etaIdle']);

  unless ($jsonData) {
    $log->error("error $jsonData");
    return 0;
  }

  # setup the new vars
  my $data = ();
  $data->{'stats'}->{'total'} = 0;
  my $tPayload = $jsonData->{'torrents'};

  my @deleted;

  $log->debug("parsing payload");
  foreach my $torrent ( @{$tPayload}) {
    my $id = int($torrent->{'id'});
    $data->{'torrents'}->{$id} = $torrent;

    # manipulate the statuses
    my $status = $torrent->{'status'};
    if ($status == 0) {
      $status = "Stopped";
    } elsif ($status == 1) {
      $status = "CheckWait";
    } elsif ($status == 2) {
      $status = "Checking";
    } elsif ($status == 3) {
      $status = "Queued";
    } elsif ($status == 4) {
      $status = "Downloading";
    } elsif ($status == 5) {
      $status = "QueuedSeed";
    } elsif ($status == 6) {
      $status = "Seeding";
    } else {
      $log->error("found unknown status $status");
    }

    # if its downloading, but no peers, its idle
    if ((!$torrent->{'peersSendingToUs'}) && ($status eq "Downloading")) {$status = "Idle"; };

    # error handling
    if ($torrent->{'error'}) {
      if (($torrent->{'errorString'} =~ /unregistered/i) || ($torrent->{'errorString'} =~ /deleted/i)) {
        $log->debug("unregistered: marking $id");
        $status = 'deleted';
        my $jsonData = encode_json $torrent;
        push(@deleted, $id);
      }
    }

    # store the status
    $data->{'torrents'}->{$id}->{'status'} = $status;

    # store it by status
    $data->{'byStatus'}->{$status}->{$id} = $id;

    # store speed
    $data->{'stats'}->{'uSpeed'} += $torrent->{'rateUpload'};
    $data->{'stats'}->{'dSpeed'} += $torrent->{'rateDownload'};

    # calculate the ratio stuff
    if ($torrent->{'uploadRatio'} == 0) {
      $data->{'stats'}->{'ratio0'}++;
    }
    if ($torrent->{'uploadRatio'} < 1) {
      $data->{'stats'}->{'ratioLT1'}++;
    }
    if ($torrent->{'uploadRatio'} >= 1) {
      $data->{'stats'}->{'ratioGT1'}++;
    }
    if ($torrent->{'uploadRatio'} >= 2) {
      $data->{'stats'}->{'ratioGT2'}++;
    }

    # totals
    $data->{'stats'}->{$status}++;
    $data->{'stats'}->{'total'}++;

  } # end of payload check`

  # process deleted
  if ($config->{'doDelete'}) {
    my $delCount = @deleted;
    if ($delCount) {
      $log->info("deleting $delCount files");
      # make the rpc request to purge all ids
      $tClient->torrent(purge => \@deleted);
    }
  } # end delete check

  $log->debug("found $data->{'stats'}->{'total'} torrents");
  return $data;
}
