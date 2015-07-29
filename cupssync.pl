#!/usr/bin/perl
#
# Name:cupssync.pl
# Script to keep the printer configs on the primary and secondary cups servers in sync.
# Intial Creation - Justin Roberts - 8/12/2014
# Added -E to creation - Justin Roberts - 7/29/2015

use strict;
use warnings;

########### CONFIGS ##################
my $primary = "cups1.local";
my $secondary = "cups2.local";
my @servers = ($primary,$secondary);
my $configlocation = "/etc/cups/printers.conf";
my $logfile = "/var/log/cupssync.log";
my $logsize = `wc -l $logfile | cut -f1 -d ' '`;
my $logmax = 500;
my $logpurge = 100;
my $localhost = `hostname -f`;
chomp($localhost);
my $currentprinter = '';
my $hash = ();
my @pconf = '';

######### MAIN CODE (DO NOT EDIT) #########
#Lets loop through each cups server and dump their printer configs
foreach my $server(@servers){
  if ($server eq $localhost){
    open (FH ,"< $configlocation") or die "$!\n";
      @pconf = <FH>;
    close(FH);
  } else {
    @pconf = `/usr/bin/ssh -l root $server cat $configlocation`;
  }

  #anylize each line of the config and build a hash
  foreach my $line(@pconf) {
    if ($line =~ /<Printer /) { # found a new printer
      my @printerline = split(/[<,\s,>]/, $line);
      $currentprinter = $printerline[2];
    } elsif (($line =~ /<\/Printer>/) || ($line =~ /^#/)) {
      next; #skip comments and printer config closing marks
    } else {
      # for each parameter of a config, get setting and put it all in the hash
      my($param,$setting) = split(/ /, $line,2);
      chomp($param);
      chomp($setting);
      $hash->{$server}{$currentprinter}{$param} .= $setting;
    }
  }
}

# Just some log file management, move along
if ($logsize > $logmax) {
  system("sed -i -e 1," . $logpurge . "d $logfile");
  print localtime() . " - LOG - Removed $logpurge lines from file\n";
}


open (LOG, ">> $logfile");

# Iterate over each printer on the primary cups server
for my $key_printers ( keys %{$hash->{ $primary }} ) {
  # Pulling config info for primary printer config
  my $deviceuri = $hash->{ $primary }{ $key_printers }{'DeviceURI'};
  my $info = $hash->{ $primary }{ $key_printers }{'Info'};
  my $location = $hash->{ $primary }{ $key_printers }{'Location'};

  # If printer exist on both check they are configured the same
  if(exists $hash->{$secondary}{$key_printers}) {
    # pull config info for secondary printer config
    # NOTE: Location and Info configs are only added/modifyied if they exist
    # NOTE: Double qoutes are perserved if present in config value

    my $deviceuri_sec = $hash->{ $secondary }{ $key_printers }{'DeviceURI'};
    my $info_sec = $hash->{ $secondary }{ $key_printers }{'Info'};
    my $location_sec = $hash->{ $secondary }{ $key_printers }{'Location'};
    my $cmd;

    # change it on secondary if different
    if ($deviceuri ne $deviceuri_sec) {
      $cmd .= " -v $deviceuri";
    }
    if ((defined $info) && (defined $info_sec)) {
      if ($info ne $info_sec) {
        $info =~ s/"/\\\\\\"/g;
        $cmd .= " -D \\\"$info\\\"";
      }
    }
    if ((defined $location) && (defined $location_sec)) {
      if ($location ne $location_sec) {
        $location =~ s/"/\\\\\\"/g;
        $cmd .= " -L \\\"$location\\\"";
      }
    }
    if (defined $cmd) {
      $cmd = "/usr/bin/ssh -l root $secondary \"/usr/sbin/lpadmin -p $key_printers $cmd\"";
      print LOG localtime() . " - DIFF - $key_printers on $secondary - CMD=$cmd\n";
      my $output = `$cmd`;
    }
  }else{ # If it doesn't exist on the secondary, add it
    my $cmd = "/usr/sbin/lpadmin -E -p $key_printers -v $deviceuri";
    if (defined $location) {
      $location =~ s/"/\\\\\\"/g;
      $cmd .= " -L \\\"$location\\\"";
    }
    if (defined $info) {
      $info =~ s/"/\\\\\\"/g;
      $cmd .= " -D \\\"$info\\\"";
    }
    $cmd = "/usr/bin/ssh -l root $secondary \"$cmd\"";
    print LOG localtime() . " - ADD - CMD=$cmd\n";
    my $output = `$cmd`;
  }
}

# Check if printers have been removed from the primary and delete them from secondary
for my $key_printers ( keys %{$hash->{ $secondary }} ) {
  if(!exists $hash->{$primary}{$key_printers}) {
    my $cmd = "/usr/bin/ssh -l root $secondary \"/usr/sbin/lpadmin -x $key_printers\"";
    print LOG localtime() . " - DELETE - CMD=$cmd\n";
    my $output = `$cmd`;
  }
}
close(LOG);
exit 0;
