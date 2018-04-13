#!/usr/bin/perl -w
#
# Released under DWTFYWTPL
# (Do What The F*ck You Want To Public License)
#
#
# Munin plugin to read IPMI sensor data
#
# Usage: put the attached ipmiget or hpasmcliget into a desired place, then 
# put it into your crontab, and make sure that /tmp is writable.
#
#        Symlink this script into your /etc/munin/plugins directory in the
#        following way:
#
#	 ipmisens2_[machine]_[sensors]
#	 Supported machines:
#	 - Sun X4100/4200: x4x00 (temp, volt, fan)
#	 - Sun V20z (V40z?): v20z (temp, volt, fan)
#	 - IBM X346: x346 (temp, volt, fan)
#	 - Sun X2100: x2100 (temp, volt, fan)
#	 - HP DL385: dl385 (temp, fan)
#	 - Asus K8N-LR + ASMB2 IPMI board: asmb2 (temp, volt, fan)
#	 - HP DL385G2: dl385g2 (temp, fan)
#	 - Intel SHG2 mainboard: shg2 (temp, volt, fan)
#
#
# Supported machines (Output submitted by):
#   - Sun V20z (Zoltan LAJBER <lajbi@lajli.gau.hu>)
#   - IBM X346 (Gergely MADARASZ <gorgo@broadband.hu>)
#   - Sun X4100 (Zoltan HERPAI <wigyori@uid0.hu>)
#   - Sun X2100 (Zoltan HERPAI <wigyori@uid0.hu>)
#   - HP DL385 (Zoltan HERPAI <wigyori@uid0.hu>)
#   - Asus K8N-LR + ASMB2 IPMI board (Louis van Belle <louis@van-belle.nl>)
#   - HP DL385G2 (Zoltan HERPAI <wigyori@uid0.hu>)
#   - Intel SHG2 mainboard (Andras GOT <andrej@antiszoc.hu>)
#
# Revision 1.0  2006/05/13 Zoltan HERPAI <wigyori@uid0.hu>
#               * Original script was done by Richard van den Berg
#               * Initial fork from Zoltan LAJBER's V20z monitorint script
#               * Added support for IBM X346, done by Gergely MADARASZ
#               * Added support for Sun X4100
#
# Revision 2.0  2006/09/28 Zoltan HERPAI <wigyori@uid0.hu>
#		* Complete rewrite in shellscript, same machines supported,
#		  thanks for the ipmitool outputs
#
# Revision 2.01	2006/09/29 Zoltan HERPAI <wigyori@uid0.hu>
#		* Added support for Sun X2100
#
# Revision 2.02	2006/10/03 Zoltan HERPAI <wigyori@uid0.hu>
#		* Added support for HP DL385
#		  Modify hpasmcliget to invoke hpasmcli from the correct
#		  location
#
# Revision 2.03 2007/01/02 Zoltan HERPAI <wigyori@uid0.hu>
#		* Added support for Asus K8N-LR + ASMB2 IPMI board
#		  Thanks to Louis van Belle for the patch and the output
#
# Revision 2.04	2007/01/20 Zoltan HERPAI <wigyori@uid0.hu>
#		* Added support for HP DL385G2
#		  Use the same hpasmcliget script for reading sensors
#		* Added support for Intel SHG2 mainboard
#		  Thanks to Andras GOT for the output
#

use strict;
use File::Basename;
use IO::File;

my(undef, $machine, $sensors) = split(/_/, basename($0));
my $ipmioutput = '/tmp/ipmi-sensors';
my @ipmioutput = ();
my %data = ();
my %graph_info =
  (
   'fan' => 'Fan speed data reported by ipmitool.',
   'temp' => 'CPU, backplane, riser, etc. temperature data reported by ipmitool.  If you see negative temperature values, note that some generations of Intel CPUs report temperature relative to critical level.  If you see vague labels such as "Temp" or "Temp 2", unfortunately that is all the data ipmitool gives.',
   'volt' => 'Voltage data reported by ipmitool.',
  );
my %graph_title =
  (
   'fan' => 'Fan speed',
   'temp' => 'Temperature',
   'volt' => 'Voltage',
  );
my %graph_vlabel =
  (
   'fan' => 'RPM',
   'temp' => 'Degrees C',
   'volt' => 'Volts',
  );

sub read_output() {
  return if(@ipmioutput);

  my $fh = IO::File->new();
  $fh->open("<$ipmioutput") || die("Could not open $ipmioutput for reading: $!\n");
  my %labelseen = ();
  my $line;
  while(defined($line = <$fh>)) {
    chomp($line);
    push(@ipmioutput, $line);
    my($name, $value, $ok) = split(/\|/, $line, 4);
    $name = &strip_spaces($name);
    $value = &strip_spaces($value);
    my $label = lc($name);
    $label =~ s/\s+temp$//;
    $label =~ s/\s+rpm$//;
    $label =~ s/\s+//g;
    my $sensors;
    if(($name =~ /temp/i) || ($value =~ /degrees/i)) {
      $sensors = 'temp';
    } elsif(($name =~ /rpm/i) || ($value =~ /rpm/i)) {
      $sensors = 'fan';
    } elsif($value =~ /volts/i) {
      $sensors = 'volt';
    } else {
      next;
    }
    $value =~ s/\s+\D+//;
    # Deal with duplicate names/labels
    if($labelseen{$label}++) {
      my $n = $labelseen{$label};
      $label = sprintf('%s_%d', $label, $n);
      $name .= sprintf(' %d', $n);
    }
    # Store in %data
    push(@{$data{$sensors}}, { name => $name, label => $label, value => $value });
  }
  $fh->close();
}

sub strip_spaces($) {
  my($str) = @_;
  $str =~ s/^\s+//;
  $str =~ s/\s+$//;
  return($str);
}

# config print

if($ARGV[0] && ($ARGV[0] eq 'autoconf')) {
  print("yes\n");
  exit 0;
}

if($ARGV[0] && ($ARGV[0] eq 'config')) {
  &read_output();
  print("graph_category sensors\n");
  printf("graph_info %s\n", $graph_info{$sensors});
  printf("graph_title %s\n", $graph_title{$sensors});
  printf("graph_vlabel %s\n", $graph_vlabel{$sensors});
  if($machine eq '0k0710') {
    foreach my $href (@{$data{$sensors}}) {
      printf("%s.label %s\n", $href->{label}, $href->{name});
    }
  }
  exit 0;
}

# printing values

&read_output();
if($machine eq '0k0710') {
  foreach my $href (@{$data{$sensors}}) {
    printf("%s.value %s\n", $href->{label}, $href->{value});
  }
}
