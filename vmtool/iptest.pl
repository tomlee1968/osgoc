#!/usr/bin/perl

use warnings;
use strict;

use NetAddr::IP;
use Socket qw(SOCK_RAW :addrinfo);

my $testhost = 'thomlee.grid.iu.edu';

sub getips($) {
  my($h) = @_;
  my($getaddr_err, @res) = getaddrinfo($h, '', {socktype => SOCK_RAW});
  if($getaddr_err) {
    warn sprintf("Unable to resolve hostname %s: %s\n", $h, $getaddr_err);
    return undef;
  }
  my @ips = ();
  foreach my $rec (@res) {
    if($rec->{addr}) {
      my(undef, $ipaddr) = getnameinfo $rec->{addr}, NI_NUMERICHOST, NIx_NOSERV;
      my $ip = NetAddr::IP->new($ipaddr);
      if(defined $ip) {
	push @ips, $ip;
      } else {
	warn "IP address invalid: %s\n", $ipaddr;
	next;
      }
    } else {
      warn "Undefined IP address\n";
      next;
    }
  }
  return \@ips;
}

my $ips = getips $testhost;
if(defined $ips) {
  foreach my $ip (@$ips) {
    printf "%s (IPv%s)\n", $ip->canon, $ip->version;
  }
}
