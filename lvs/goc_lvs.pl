#!/usr/bin/perl

# goc_lvs.pl -- configure LVS and firewall based on single config file
# Tom Lee <thomlee@iu.edu>
# Begun 2015-01-16
# Last modified 2016-07-07

# This requires the following RPMs, all standard with RHEL/CentOS:
# perl-Net-DNS
# perl-NetAddr-IP
# perl-YAML

use strict;
use warnings;
use Getopt::Std;
use IO::File;
use Net::DNS;
use NetAddr::IP;
use Scalar::Util qw(looks_like_number);
use Storable qw(dclone);
use Sys::Hostname;
use YAML;

###############################################################################
# Settings
###############################################################################

# Path to YAML config file (ordinarily
# /usr/local/lvs/etc/goc_lvs.conf)
my $CONFIG = '/usr/local/lvs/etc/goc_lvs.conf';

# Path to write firewall config snippet to (ordinarily
# /etc/iptables.d/lvs_hostdata)
my $FW_LVS_HOSTDATA = '/etc/iptables.d/lvs_hostdata';

# Path to write LVS config file to (ordinarily
# /etc/keepalived/keepalived.conf)
my $LVS_CONFIG = '/etc/keepalived/keepalived.conf';

# Max number of VIPs per instance (this is 20 for keepalived, at least)
my $MAX_VIPS = 20;

# IPv4 and IPv6 prefixes for public and private VLANs
my %PREFIX =
  (
   public =>
   {
    ipv4 => NetAddr::IP->new('129.79.53.0/24'),
    ipv6 => NetAddr::IP->new('2001:18e8:2:6::/64'),
   },
   private =>
   {
    ipv4 => NetAddr::IP->new('192.168.96.0/22'),
    ipv6 => NetAddr::IP->new('fd2f:6feb:37::/48'),
   },
  );

# Version
$main::VERSION = '1.0';

###############################################################################
# Globals
###############################################################################

# Debug mode (print extra output)
my $DEBUG = '';

# Test mode (don't do anything; print what would be done)
my $TEST = '';

# Update group ('' means normal; -u option changes)
my $UPDATE_GROUP = '';

# Realservers to remove (empty = normal; -r option changes)
my @REMOVED_REALSERVERS = ();

# Set the path to prevent tainted input
$ENV{PATH} = '/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin';

# Hash in which to store the data from the config file
my %CONFIG = ();

# Command-line options
my %OPT = ();

# Information about this server
my %INFO = ();

# DNS cache
my %DNSCACHE = ();

###############################################################################
# Subroutines
###############################################################################

sub main::VERSION_MESSAGE() {
  # Print the version.
  printf "This is goc_lvs.pl version %s\n", $main::VERSION;
}

sub main::HELP_MESSAGE() {
  # Print help.
  print <<"EOF";
Usage:
goc_lvs.pl [<options>]
  Options:
  -c: Print a brief summary of the config file data.
  -d: Debug mode (extra output)
  -h: Print this help message
  -o: Print a brief summary of the current status (old format).
  -p: Print a brief summary of the current status.
  -r <label>[,<label>...]: Remove labeled realservers temporarily.
  -t: Test mode (don't do anything, but print what would be done)
  -u <group>: Disable hosts that are disabled for the given update group
  -v: Print version

To print the current state of ipvsadm (the running state, not the state in this
script's config file):
# goc_lvs.pl -p

To restore things to the state in the config file ($CONFIG):
# goc_lvs.pl
EOF
  ;
}

sub debug_printf($@) {
  # Print something, but only if we're in debug mode.  Given a format and a
  # list of data items, print to standard output with a debug mode prefix and a
  # built-in newline -- but only if $DEBUG is true.  If it isn't, print
  # nothing.
  my($fmt, @data) = @_;
  printf '*** DEBUG: '.$fmt."\n", @data if $DEBUG;
}

sub test_printf($@) {
  # Print something, indicating that we're in test mode (and probably that if
  # we weren't, this is what would have happened).  Given a format and a list
  # of data items, print to standard output with a test mode prefix and a
  # built-in newline.
  my($fmt, @data) = @_;
  printf '(test mode) '.$fmt."\n", @data;
}

sub compare_scalars($$) {
  # Returns true if the arguments are equal, false otherwise. If one
  # of the two is numeric, compare numerically; otherwise, compare as
  # strings.
  my($a, $b) = @_;
  my $anumeric = looks_like_number $a;
  my $bnumeric = looks_like_number $b;
  my $bothnumeric = ($anumeric and $bnumeric);
  my $onenumeric = ($anumeric or $bnumeric);
  return '' if $onenumeric and !$bothnumeric;
  if($bothnumeric) {
    return $a == $b;
  } else {
    return $a eq $b;
  }
}

sub compare_arrays($$) {
  # Returns true if the arguments are both references to arrays with
  # identical contents (identical in both content and order). Returns
  # false if there are any differences.

  my($a, $b) = @_;
  # Obviously they can't be identical arrays unless they're both
  # arrays.
  return '' unless ref $a eq 'ARRAY' and ref $b eq 'ARRAY';
  # They also can't be identical arrays unless they have the same
  # length.
  return '' if $#$a != $#$b;
  # If even one element differs, return false.
  for(my $i = 0; $i <= $#$a; $i++) {
    return '' unless compare_objects($a->[$i], $b->[$i]);
  }
  # At this point they must be identical.
  return 1;
}

sub compare_hashes($$) {
  # Returns true if the arguments are both references to hashes with
  # identical contents (identical keys and identical values for each
  # key). Returns false if there are any differences.

  my($a, $b) = @_;
  # Obviously they can't be identical hashes unless they're both
  # hashes.
  return '' unless ref $a eq 'HASH' and ref $b eq 'HASH';
  # They must have the same key arrays if they're identical.
  my @akeys = sort keys %$a;
  my @bkeys = sort keys %$b;
  return '' unless compare_arrays \@akeys, \@bkeys;
  # If even one value differs, return false.
  foreach my $key (@akeys) {
    return '' unless compare_objects($a->{$key}, $b->{$key});
  }
  # At this point the must be identical.
  return 1;
}

sub compare_objects($$) {
  # Returns true if the arguments are identical and false if
  # not. Attempts to compare them based on what they are; calls
  # compare_arrays, compare_hashes, or compare_scalars if
  # necessary. Returns undef if both are references to a type this
  # subroutine doesn't handle.
  my($a, $b) = @_;
  # If they're both undef, they're equal.
  return 1 if !defined $a and !defined $b;
  # If one is undef and the other is not, they're not equal.
  return '' if !defined $a or !defined $b;
  # At this point neither is undef. See if either is a ref.
  my $refa = ref $a;
  my $refb = ref $b;
  # If neither is a ref, both are scalars; compare them as such.
  return compare_scalars $a, $b if $refa eq '' and $refb eq '';
  # If one is a ref and the other is not, they can't be equal.
  return '' if $refa eq '' or $refb eq '';
  # At this point both are refs. If they're not refs to the same type,
  # they're not equal.
  return '' if $refa ne $refb;
  # At this point they're refs to the same type.
  return compare_scalars $a, $b if $refa eq 'SCALAR';
  return compare_arrays $a, $b if $refa eq 'ARRAY';
  return compare_hashes $a, $b if $refa eq 'HASH';
  # At this point they're both refs to a type this subroutine doesn't
  # handle.
  return undef;
}

sub dns_query($$) {
  # Returns an array of Net::DNS::RR::<type> objects based on the DNS
  # record type and query given.  Answer from cache if possible.
  my($type, $search) = @_;
  return () unless $type and $search;
  my @return = ();
  # If the query matches a CNAME, it gets returned regardless of what
  # else gets returned.  That's how regular DNS queries work too; try
  # it with 'dig'.
  if(exists $DNSCACHE{CNAME}->{$search}) {
    push @return, @{$DNSCACHE{CNAME}->{$search}};
  }
  if(exists $DNSCACHE{$type}->{$search}) {
    # Of course, if the record itself is cached, return that too.
    push @return, @{$DNSCACHE{$type}->{$search}};
    return @return;
  } else {
    # The requested record wasn't in the cache, so search DNS for it.
    my $res = Net::DNS::Resolver->new();
    my $query = $res->search($search, $type);
    unless($query) {
      warn "DNS query $type: $search returned no results\n" if $DEBUG;
      return ();
    }
    my @answers = $query->answer;
    foreach my $answer (@answers) {
      push @{$DNSCACHE{$answer->type()}->{$answer->name()}}, $answer;
      push @return, $answer;
    }
  }
  return @return;
}

sub reverse_dns($) {
  # Given an IP address, look up its hostname.  If there are more than one, just return the first one.
  my($ip) = @_;
  return undef unless $ip;
  my @results = dns_query 'PTR', $ip;
  unless(@results) {
    warn sprintf("WARNING: IP address '%s' not found in DNS\n",
		 $ip);
    return undef;
  }
  my $host = $results[0]->ptrdname();
  return $host;
}

sub read_config {
  # Read the $CONFIG file and put the results in %CONFIG.
  my %update_group = ();
  my $hashref = YAML::LoadFile($CONFIG);
  %CONFIG = %$hashref;
  # Do some tests to make sure it's formatted correctly.
  my %allowedkeys = map { $_ => 1 } qw( globals sync_groups );
  foreach my $key (keys %CONFIG) {
    unless(exists $allowedkeys{$key}) {
      die "Unknown key $key: bad config?\n";
    }
  }
  if(exists $CONFIG{globals}) {
    unless(defined $CONFIG{globals}) {
      die "'globals' value undefined: bad config?\n";
    }
    unless(ref $CONFIG{globals} eq 'HASH') {
      die "'globals' must contain a hash: bad config?\n";
    }
    %allowedkeys = map { $_ => 1 } qw ( email_to email_from smtp_server smtp_connect_timeout update_groups );
    foreach my $key (keys %{$CONFIG{globals}}) {
      unless(exists $allowedkeys{$key}) {
	die "Unknown key '$key' in 'globals': bad config?\n";
      }
    }
    if(exists $CONFIG{globals}->{email_to}) {
      unless(defined $CONFIG{globals}->{email_to}) {
	die "'globals'->'email_to' undefined: bad config?\n";
      }
      unless(ref $CONFIG{globals}->{email_to} eq 'ARRAY') {
	die "'globals'->'email_to' must contain an array: bad config?\n";
      }
    }
  }
  if(exists $CONFIG{sync_groups}) {
    unless(defined $CONFIG{sync_groups}) {
      die "'sync_groups' value undefined: bad config?\n";
    }
    unless(ref $CONFIG{sync_groups} eq 'ARRAY') {
      die "'sync_groups' must contain an array: bad config?\n";
    }
    foreach my $syncgroup (@{$CONFIG{sync_groups}}) {
      if(exists $syncgroup->{instances}) {
	unless(defined $syncgroup->{instances}) {
	  die "'instances' value of sync_group undefined: bad config?\n";
	}
	unless(ref $syncgroup->{instances} eq 'ARRAY') {
	  die "'instances' value of sync_group must contain an array: bad config?\n";
	}
	foreach my $instance (@{$syncgroup->{instances}}) {
	  unless(defined $instance) {
	    die "'instances' array contains undefined value: bad config?\n";
	  }
	  unless(ref $instance eq 'HASH') {
	    die "Members of 'instances' array must be hashes: bad config?\n";
	  }
	}
      }
      if(exists $syncgroup->{services}) {
	unless(defined $syncgroup->{services}) {
	  die "'services' value of sync_group undefined: bad config?\n";
	}
	unless(ref $syncgroup->{services} eq 'ARRAY') {
	  die "'services' value of sync_group must contain an array: bad config?\n";
	}
	foreach my $service (@{$syncgroup->{services}}) {
	  unless(defined $service) {
	    die "'services' array contains undefined value: bad config?\n";
	  }
	  unless(ref $service eq 'HASH') {
	    die "Members of 'services' array must be hashes: bad config?\n";
	  }
	  if(exists $service->{real_servers}) {
	    unless(defined $service->{real_servers}) {
	      die "'real_servers' value of service '$service->{label}' undefined: bad config?\n";
	    }
	    unless(ref $service->{real_servers} eq 'ARRAY') {
	      die "'real_servers' value of service '$service->{label}' must contain an array: bad config?\n";
	    }
	    foreach my $rs (@{$service->{real_servers}}) {
	      if(exists $rs->{disabled_in}) {
		unless(defined $rs->{disabled_in}) {
		  die "'disabled_in' for real server '$rs->{label}' has undefined value: bad config?\n";
		}
		unless(ref $rs->{disabled_in} eq 'ARRAY') {
		  die "'disabled_in' for real server '$rs->{label}' does not contain array: bad config?\n";
		}
		foreach my $ug (@{$rs->{disabled_in}}) {
		  unless(defined $ug) {
		    die "'disabled_in' array for real server '$rs->{label}' contains an undefined value: bad config?\n";
		  }
		  $update_group{$ug} = 1;
		}
	      }
	    }
	  }
	}
      }
    }
  }
  my @update_groups = sort keys %update_group;
  if($#update_groups > -1) {
    $CONFIG{derived}->{update_groups} = \@update_groups;
  }
}

sub print_lvs_str($) {
  my($str) = @_;
  my $str2 = $str;
  $str2 =~ s/&/\n/g;
  $str2 =~ s/;/\n/g;
  $str2 =~ s/\//\n  /g;
  $str2 =~ s/\|?>/\n    -> /g;
  $str2 =~ s/\|/\n  /g;
  $str2 =~ s/!/: /g;
  $str2 =~ s/,/, /g;
  printf "%s\n", $str2;
}

sub print_config() {
  # Print a concise summary of the config file.
  foreach my $sg (sort @{$CONFIG{sync_groups}}) {
    printf "Sync group %s: instances %s\n",
      $sg->{label},
	(join ', ', sort map { $_->{label} } @{$sg->{instances}});
    foreach my $service (sort { $a->{label} cmp $b->{label} } @{$sg->{services}}) {
      my @sflags = ();
      push @sflags, 'noipv6' if exists $service->{noipv6};
      my $sflags = '';
      $sflags = sprintf ' (%s)', (join ', ', sort @sflags) if @sflags;
      printf "  Service %s: port %s%s\n", $service->{label},
	$service->{forward}, $sflags;
      foreach my $rs (sort { $a->{label} cmp $b->{label} } @{$service->{real_servers}}) {
	my @rflags = ();
	push @rflags, 'disabled' if exists $rs->{disabled};
	push @rflags, sprintf 'except %s', $rs->{forward_except} if exists $rs->{forward_except};
	my $rflags = '';
	$rflags = sprintf ' (%s)', (join ', ', sort @rflags) if @rflags;
	printf "    -> %s%s\n", $rs->{label}, $rflags;
      }
    }
  }
}

sub print_status() {
  # Look at 'ipvsadm -L' output and condense it into a concise status display.
  #
  # Example output:
  #
  # IP Virtual Server version 1.2.1 (size=4096)
  # Prot LocalAddress:Port Scheduler Flags
  #   -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
  # TCP  129.79.53.99:80 rr persistent 600
  #   -> 129.79.53.54:80              Route   100    0          41
  # TCP  129.79.53.99:2170 rr persistent 600
  #   -> 129.79.53.54:2170            Route   100    0          1
  # TCP  129.79.53.99:2180 rr persistent 600
  #   -> 129.79.53.54:2180            Route   100    0          0
  # TCP  129.79.53.134:25 rr persistent 600
  #   -> 129.79.53.97:25              Route   100    0          0
  # TCP  129.79.53.134:80 rr persistent 600
  #   -> 129.79.53.97:80              Route   100    0          0
  # TCP  [2001:18e8:2:6::17d]:80 rr persistent 600
  #   -> [2001:18e8:2:6::113]:80      Route   100    0          0
  # TCP  [2001:18e8:2:6::17d]:2170 rr persistent 600
  #   -> [2001:18e8:2:6::113]:2170    Route   100    0          0
  # TCP  [2001:18e8:2:6::17d]:2180 rr persistent 600
  #   -> [2001:18e8:2:6::113]:2180    Route   100    0          0
  # TCP  [2001:18e8:2:6::19a]:25 rr persistent 600
  #   -> [2001:18e8:2:6::12f]:25      Route   100    0          0
  # TCP  [2001:18e8:2:6::19a]:80 rr persistent 600
  #   -> [2001:18e8:2:6::12f]:80      Route   100    0          0
  my @output = `ipvsadm -L -n`;
  my %lvsdata = ();
#  my($vip, $vhost, $vport) = (undef, undef, undef);
  my($prot, $vip, $vipv, $vhost, $vshort, $vport, $sched, @flags);
  foreach my $line (@output) {
    # Skip first header line.
    next if $line =~ /^IP Virtual Server version/;
    chomp $line;
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    my @items = split /\s+/, $line;
    # If $items[0] is 'Prot', this is the second header line.
    next if $items[0] eq 'Prot';
    # If $items[0] is '->' and $items[1] is 'RemoteAddress:Port', this
    # is the third header line.
    next if $items[0] eq '->' and $items[1] eq 'RemoteAddress:Port';
    # If $items[0] is '->', this is a realserver line associated with
    # the last VIP line encountered.
    if($items[0] eq '->') {
      shift @items;
      my($rap, $fwd, $wgt, $ac, $ic) = @items;
      my($rip, $rport) = ($rap =~ /^(.*):(\d+)$/);
      $rip =~ s/^\[//;
      $rip =~ s/\]$//;
      my $rhost = reverse_dns $rip;
      if($rhost) {
	my($rshort) = split /\./, $rhost, 2;
	push @{$lvsdata{$vhost}->{$rhost}->{$vipv}}, $rport;
      }
    } else {
      # This is a VIP line that will change the value of $vip, $vport,
      # etc.
      my($vap);
      ($prot, $vap, $sched, @flags) = @items;
      ($vip, $vport) = ($vap =~ /^(.*):(\d+)$/);
      if($vip =~ /^\[/) {
	$vipv = 'ipv6';
      } else {
	$vipv = 'ipv4';
      }
      $vip =~ s/^\[//;
      $vip =~ s/\]$//;
      $vhost = reverse_dns $vip;
      if($vhost) {
	($vshort) = split /\./, $vhost, 2;
      } else {
	$vshort = '';
      }
    }
  }

  # Sort the ports.
  while(my($vhost, $vhostdata) = each %lvsdata) {
    while(my($rhost, $rhostdata) = each %$vhostdata) {
      while(my($vipv, $vipvports) = each %$rhostdata) {
	next if $#$vipvports == -1;
	$rhostdata->{$vipv} = [ sort { $a <=> $b } @$vipvports ];
      }
    }
  }

  # Replace 'ipv4' and 'ipv6' with 'all' when the port lists are the
  # same.
  while(my($vhost, $vhostdata) = each %lvsdata) {
    while(my($rhost, $rhostdata) = each %$vhostdata) {
      my $common_vipvports = $rhostdata->{(keys %$rhostdata)[0]};
      foreach my $vipv (qw(ipv4 ipv6)) {
	my $vipvports = $rhostdata->{$vipv};
	unless(compare_objects $vipvports, $common_vipvports) {
	  $common_vipvports = undef;
	  last;
	}
      }
      if(defined $common_vipvports) {
	foreach my $vipv (keys %$rhostdata) {
	  delete $rhostdata->{$vipv};
	}
	$rhostdata->{all} = $common_vipvports;
      }
    }
  }

  # Transform the data into something resembling the configuration
  # data structure, replacing IPv4-only with 'noipv6'.
  my %lvsdata_conf = ( 'services' => [] );
  while(my($vhost, $vhostdata) = each %lvsdata) {
    # First start off the service record.
    my($vshort) = split /\./, $vhost, 2;
    $vshort =~ s/^vip-//;
    my $srec = {
		label => $vshort,
		vip => $vhost,
	       };
    # Now perform some checks on all the service's realservers. This
    # one checks whether no realservers are forwarding IPv6.
    my $no_rhost_has_ipv6 = 1;
    while(my($rhost, $rhostdata) = each %$vhostdata) {
      $no_rhost_has_ipv6 = '' if exists $rhostdata->{ipv6} or exists $rhostdata->{all};
    }
    $srec->{noipv6} = 1 if $no_rhost_has_ipv6;

    # This one sees whether all realservers are forwarding the same
    # ports for IPv4 (and IPv6, unless it isn't forwarding that).
    my $most_ports = [];
    while(my($rhost, $rhostdata) = each %$vhostdata) {
      while(my($vipv, $vipvports) = each %$rhostdata) {
	$most_ports = $vipvports if $#$vipvports > $#$most_ports;
      }
    }
    # $most_ports now contains the longest port list.
    while(my($rhost, $rhostdata) = each %$vhostdata) {
      # Start off the realserver record.
      my $rrec = {
		  label => (split /\./, $rhost, 2)[0],
		  rip => $rhost,
		 };
      # Now see if there are any exceptions to $most_ports.
      my @exceptions = ();
      while(my($vipv, $vipvports) = each %$rhostdata) {
	next if $#$vipvports == -1;
	my %port_present = map { $_ => 1 } @$vipvports;
	foreach my $port (@$most_ports) {
	  push @exceptions, $port unless exists $port_present{$port};
	}
      }
      $rrec->{forward_except} = sprintf('TCP/%s', join ',', @exceptions) if $#exceptions > -1;
      $srec->{forward} = sprintf('TCP/%s', join ',', @$most_ports);
      $srec->{forward} =~ s/TCP\/0/TCP\/*/;
      push @{$srec->{real_servers}}, $rrec;
    }
    push @{$lvsdata_conf{services}}, $srec;
  }

  # Now go through the configured services and see how things match up.
  foreach my $sg (sort @{$CONFIG{sync_groups}}) {
    foreach my $service (sort { $a->{label} cmp $b->{label} } @{$sg->{services}}) {
      my @srecs = grep { $_->{label} eq $service->{label} } @{$lvsdata_conf{services}};
      unless($#srecs > -1) {
	printf "  Service %s: *** MISSING ***\n", $service->{label};
	next;
      }
      my $srec = $srecs[0];
      my @sflags = ();
      if(exists $srec->{noipv6}) {
	my $noipv6flag = 'noipv6';
	unless(exists $service->{noipv6}) {
	  $noipv6flag .= ' [contrary to config; no IPv6 in DNS?]';
	}
	push @sflags, $noipv6flag;
      } else {
	if(exists $service->{noipv6}) {
	  push @sflags, '[ignoring noipv6 in config]'
	}
      }
      my $sflags = '';
      $sflags = sprintf ' (%s)', (join ', ', sort @sflags) if @sflags;
      my $forward = $srec->{forward};
      if($forward ne $service->{forward}) {
	$forward .= sprintf ' [config has %s]', $service->{forward};
      }
      printf "  Service %s: port %s%s\n", $service->{label},
	$forward, $sflags;
      foreach my $rs (sort { $a->{label} cmp $b->{label} } @{$service->{real_servers}}) {
	my @rrecs = grep { $_->{label} eq $rs->{label} } @{$srec->{real_servers}};
	unless($#rrecs > -1) {
	  if(exists $rs->{disabled}) {
	    printf "    (%s unsurprisingly missing; disabled in config)\n", $rs->{label};
	  } else {
	    printf "    (%s missing; disabled from command line?)\n", $rs->{label};
	  }
	  next;
	}
	my $rrec = $rrecs[0];
	my @rflags = ();
	if(exists $rrec->{forward_except}) {
	  my $exceptflag = sprintf 'except %s', $rrec->{forward_except};
	  if($rs->{forward_except} ne $rrec->{forward_except}) {
	    $exceptflag .= sprintf ' [config has %s]', $rs->{forward_except};
	  }
	  push @rflags, $exceptflag;
	} else {
	  if(exists $rs->{forward_except}) {
	    push @rflags, (sprintf ' [ignoring forward_except = %s in config]',
			   $rs->{forward_except});
	  }
	}
	my $rflags = '';
	$rflags = sprintf ' (%s)', (join ', ', sort @rflags) if @rflags;
	printf "    -> %s%s\n", $rs->{label}, $rflags;
      }
    }
  }

  # Now print the data.  The normal circumstance would be for both IPv4 and
  # IPv6 to be forwarded the same way.  Call attention to it only if that's not
  # the case.
  #
  # Short output format for each vhost:
  # vhost:
  #   vport1,vport2:
  #     rhost1,rhost2
  #
  # Long output format, the most general:
  # vhost_ipv4:
  #   vport_ipv4_1:
  #     rhost_ipv4_1_1:rport_ipv4_1_1
  #     rhost_ipv4_1_2:rport_ipv4_1_2
  #   vport_ipv4_2:
  #     rhost_ipv4_2_1:rport_ipv4_2_1
  #     rhost_ipv4_2_2:rport_ipv4_2_2
  # vhost_ipv6:
  #   vport_ipv6_1:
  #     rhost_ipv6_1_1:rport_ipv6_1_1
  #     rhost_ipv6_1_2:rport_ipv6_1_2
  #   vport_ipv6_2:
  #     rhost_ipv6_2_1:rport_ipv6_2_1
  #     rhost_ipv6_2_2:rport_ipv6_2_2
  #
  # The general long output gets shorter the closer the situation comes to the
  # common case.  If rport_ipvX_Y_* are equal, their rhosts could be combined
  # into a comma-separated list:
  #
  # vhost_ipv4:
  #   vport_ipv4_1:
  #     rhost_ipv4_1_1,rhost_ipv4_1_2:rport_ipv4_1
  #   vport_ipv4_2:
  #     rhost_ipv4_2_1,rhost_ipv4_2_2:rport_ipv4_2
  # vhost_ipv6:
  #   vport_ipv6_1:
  #     rhost_ipv6_1_1,rhost_ipv6_1_2:rport_ipv6_1
  #   vport_ipv6_2:
  #     rhost_ipv6_2_1,rhost_ipv6_2_2:rport_ipv6_2
  #
  # If rport_ipvX_Y is equal to vport_ipvX_Y, the rport could be omitted as
  # understood:
  #
  # vhost_ipv4:
  #   vport_ipv4_1:
  #     rhost_ipv4_1_1,rhost_ipv4_1_2
  #   vport_ipv4_2:
  #     rhost_ipv4_2_1,rhost_ipv4_2_2
  # vhost_ipv6:
  #   vport_ipv6_1:
  #     rhost_ipv6_1_1,rhost_ipv6_1_2
  #   vport_ipv6_2:
  #     rhost_ipv6_2_1,rhost_ipv6_2_2
  #
  # If the rhost lists for any of the vports are the same, the vports could be
  # combined into a list:
  #
  # vhost_ipv4:
  #   vport_ipv4_1,vport_ipv4_2:
  #     rhost_ipv4_1,rhost_ipv4_2
  # vhost_ipv6:
  #   vport_ipv6_1,vport_ipv6_2:
  #     rhost_ipv6_1,rhost_ipv6_2
  #
  # If the vport and rhost lists for ipv6 are the same as those for ipv4, these
  # could just be combined, and it would be fairly easy to detect this, as we'd
  # just be using hostnames:
  #
  # vhost:
  #   vport_1,vport_2:
  #     rhost_1,rhost_2
  #
  # So we're going to attempt to transform and reduce the %lvsdata that way.
  #
}

sub print_status_old() {
  # Look at 'ipvsadm -L' output and condense it into a concise status display.
  #
  # Example output:
  #
  # IP Virtual Server version 1.2.1 (size=4096)
  # Prot LocalAddress:Port Scheduler Flags
  #   -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
  # TCP  129.79.53.99:80 rr persistent 600
  #   -> 129.79.53.54:80              Route   100    0          41
  # TCP  129.79.53.99:2170 rr persistent 600
  #   -> 129.79.53.54:2170            Route   100    0          1
  # TCP  129.79.53.99:2180 rr persistent 600
  #   -> 129.79.53.54:2180            Route   100    0          0
  # TCP  129.79.53.134:25 rr persistent 600
  #   -> 129.79.53.97:25              Route   100    0          0
  # TCP  129.79.53.134:80 rr persistent 600
  #   -> 129.79.53.97:80              Route   100    0          0
  # TCP  [2001:18e8:2:6::17d]:80 rr persistent 600
  #   -> [2001:18e8:2:6::113]:80      Route   100    0          0
  # TCP  [2001:18e8:2:6::17d]:2170 rr persistent 600
  #   -> [2001:18e8:2:6::113]:2170    Route   100    0          0
  # TCP  [2001:18e8:2:6::17d]:2180 rr persistent 600
  #   -> [2001:18e8:2:6::113]:2180    Route   100    0          0
  # TCP  [2001:18e8:2:6::19a]:25 rr persistent 600
  #   -> [2001:18e8:2:6::12f]:25      Route   100    0          0
  # TCP  [2001:18e8:2:6::19a]:80 rr persistent 600
  #   -> [2001:18e8:2:6::12f]:80      Route   100    0          0
  my @output = `ipvsadm -L -n`;
  my %lvsdata = ();
  my($vip, $vhost, $vport) = (undef, undef, undef);
  foreach my $line (@output) {
    # Lines that start with 'TCP' denote a VIP:port.
    #
    # Lines that start with '->' denote a RIP:port associated with the last
    # VIP:port encountered.  (Except for the one in the header, which can be
    # ignored easily since no VIP:port will have yet been encountered.)
    if($line =~ /^\s*TCP/) {
      # This line defines a new VIP:port; the previous one is done.
      my($tcp, $vip_vport) = split /\s+/, $line, 3;
      ($vip, $vport) = ($vip_vport =~ /^(.*):(\d+)$/);
      # Strip off the [square brackets] around IPv6 addresses:
      $vip =~ s/^\[//;
      $vip =~ s/\]$//;
      $vhost = reverse_dns $vip;
      next unless $vhost;
      # Organizing these by virtual hostname, because that's how they will be
      # printed, for clarity's sake.  Each vhost can have more than one port,
      # though, and each port can (and probably will) have more than one vip
      # (the ipv4 and ipv6 addresses for the same host).
      $lvsdata{$vhost}->{$vport}->{$vip} = {};
    } elsif($line =~ /^\s*->/) {
      # The header also has a -> line, so unless we've had a VIP line that has
      # set $vip, etc., skip this line.
      next unless defined $vip and defined $vhost and defined $vport;
      $line =~ s/^\s+//;
      my(undef, $rip_rport) = split /\s+/, $line, 3;
      my($rip, $rport) = ($rip_rport =~ /^(.*):(\d+)$/);
      $rip =~ s/^\[//;
      $rip =~ s/\]$//;
      debug_printf 'Found %s (%s):%s', $rip, reverse_dns $rip, $rport;
      # For a given vhost/vport, each vip can (and probably will) have more
      # than one rip (the IPs of the various realservers), and each rip will
      # have one rport, the port to which to forward packets.
      $lvsdata{$vhost}->{$vport}->{$vip}->{$rip} = $rport;
    }
  }
  # Now print the data.  The normal circumstance would be for both IPv4 and
  # IPv6 to be forwarded the same way.  Call attention to it only if that's not
  # the case.
  #
  # Short output format for each vhost:
  # vhost:
  #   vport1,vport2:
  #     rhost1,rhost2
  #
  # Long output format, the most general:
  # vhost_ipv4:
  #   vport_ipv4_1:
  #     rhost_ipv4_1_1:rport_ipv4_1_1
  #     rhost_ipv4_1_2:rport_ipv4_1_2
  #   vport_ipv4_2:
  #     rhost_ipv4_2_1:rport_ipv4_2_1
  #     rhost_ipv4_2_2:rport_ipv4_2_2
  # vhost_ipv6:
  #   vport_ipv6_1:
  #     rhost_ipv6_1_1:rport_ipv6_1_1
  #     rhost_ipv6_1_2:rport_ipv6_1_2
  #   vport_ipv6_2:
  #     rhost_ipv6_2_1:rport_ipv6_2_1
  #     rhost_ipv6_2_2:rport_ipv6_2_2
  #
  # The general long output gets shorter the closer the situation comes to the
  # common case.  If rport_ipvX_Y_* are equal, their rhosts could be combined
  # into a comma-separated list:
  #
  # vhost_ipv4:
  #   vport_ipv4_1:
  #     rhost_ipv4_1_1,rhost_ipv4_1_2:rport_ipv4_1
  #   vport_ipv4_2:
  #     rhost_ipv4_2_1,rhost_ipv4_2_2:rport_ipv4_2
  # vhost_ipv6:
  #   vport_ipv6_1:
  #     rhost_ipv6_1_1,rhost_ipv6_1_2:rport_ipv6_1
  #   vport_ipv6_2:
  #     rhost_ipv6_2_1,rhost_ipv6_2_2:rport_ipv6_2
  #
  # If rport_ipvX_Y is equal to vport_ipvX_Y, the rport could be omitted as
  # understood:
  #
  # vhost_ipv4:
  #   vport_ipv4_1:
  #     rhost_ipv4_1_1,rhost_ipv4_1_2
  #   vport_ipv4_2:
  #     rhost_ipv4_2_1,rhost_ipv4_2_2
  # vhost_ipv6:
  #   vport_ipv6_1:
  #     rhost_ipv6_1_1,rhost_ipv6_1_2
  #   vport_ipv6_2:
  #     rhost_ipv6_2_1,rhost_ipv6_2_2
  #
  # If the rhost lists for any of the vports are the same, the vports could be
  # combined into a list:
  #
  # vhost_ipv4:
  #   vport_ipv4_1,vport_ipv4_2:
  #     rhost_ipv4_1,rhost_ipv4_2
  # vhost_ipv6:
  #   vport_ipv6_1,vport_ipv6_2:
  #     rhost_ipv6_1,rhost_ipv6_2
  #
  # If the vport and rhost lists for ipv6 are the same as those for ipv4, these
  # could just be combined, and it would be fairly easy to detect this, as we'd
  # just be using hostnames:
  #
  # vhost:
  #   vport_1,vport_2:
  #     rhost_1,rhost_2
  #
  # So we're going to attempt to transform and reduce the %lvsdata that way.
  #
  my @lvsarr = ();
  foreach my $vhost (sort keys %lvsdata) {
    my $vhostrec = $lvsdata{$vhost};
    my @vports = sort { $a <=> $b } keys %$vhostrec;
    my @vhostarr = ();
    foreach my $vport (@vports) {
      my $vportrec = $vhostrec->{$vport};
      my @vportarr = ();
      foreach my $vip (keys %$vportrec) {
	my $viprec = $vportrec->{$vip};
	my @viparr = ();
	foreach my $rip (keys %$viprec) {
	  my $rport = $viprec->{$rip};
	  my $rhost = reverse_dns $rip;
	  push @viparr, "$rhost!$rport";
	}
	push @vportarr, "$vip>".join(',', sort @viparr);
      }
      push @vhostarr, "$vhost!$vport|".join('/', @vportarr);
    }
    push @lvsarr, join(";", @vhostarr);
  }
  my $lvsstr = join("&", @lvsarr);
  my $lvsstr2 = $lvsstr;
  debug_printf '$lvsstr2 = %s', $lvsstr2;
  my $teststr;
  # Factors out rport
  do {	# rhost1!rport,rhost2!rport,... -> rhost1,rhost2,...!rport
    $teststr = $lvsstr2;
    $lvsstr2 =~ s/>([^>!\/|&;]+)!(\d+),([^>!\/|&;,]+)!\g{2}/>$1,$3!$2/g;
  } until $lvsstr2 eq $teststr;
  # Suppresses rport when it is the same as vport
  do {	# !port|vip1>rip1!port,rip2!port/vip2>rip3!port,rip4!port/... -> !port|vip1>rip1,rip2/vip2>rip3,rip4/...
    $teststr = $lvsstr2;
    $lvsstr2 =~ s/!(\d+)(\|[^;&|]*)!\g{1}/!$1$2/g;
  } until $lvsstr2 eq $teststr;
  # Factors out identical vip/rip/rport list
  do {	# host!port1|vip1>rip1,...;host!port2|vip1>vip1,... -> host!port1,port2,...|vip1>rip1,...
    $teststr = $lvsstr2;
    $lvsstr2 =~ s/([^;!]+)!([\d,]+)\|([^|;&]+);\g{1}!(\d+)\|\g{3}/$1!$2,$4|$3/g;
  } until $lvsstr2 eq $teststr;
  # Factors out identical rip list; squashes vip (all vips for vhost)
  do {	# |vip1>rip1,rip2,.../vip2>rip1,rip2,... -> |>rip1,rip2,...
    $teststr = $lvsstr2;
    $lvsstr2 =~ s/\|([^|>]+)>([^>\/]+)\/([^|>]+)>\g{2}/|>$2/g;
  } until $lvsstr2 eq $teststr;
  print_lvs_str $lvsstr2;
}

sub handle_options {
  # Handle the command-line options and put them in %OPT.
  $Getopt::Std::STANDARD_HELP_VERSION = 1;
  getopts('cdhopr:tu:v', \%OPT);
  if(exists $OPT{c}) {
    print_config;
    exit 0;
  }
  if(exists $OPT{d}) {
    $DEBUG = 1;
  }
  if(exists $OPT{v}) {
    main::VERSION_MESSAGE;
    exit 0;
  }
  if(exists $OPT{h}) {
    main::HELP_MESSAGE;
    exit 0;
  }
  if(exists $OPT{o}) {
    print_status_old;
    exit 0;
  }
  if(exists $OPT{p}) {
    print_status;
    exit 0;
  }
  if(exists $OPT{r}) {
    # Split on commas and optional whitespace around those commas.
    @REMOVED_REALSERVERS = split /\s*,\s*/, $OPT{r};

    # Make sure any mentioned realservers are actually the labels of
    # realservers in the config file.
    my %rsfound = map {
      $_ => ''
    } @REMOVED_REALSERVERS;
    my $numfound = 0;
    foreach my $sg (@{$CONFIG{sync_groups}}) {
      foreach my $service (@{$sg->{services}}) {
	foreach my $rs (@{$service->{real_servers}}) {
	  if(exists $rsfound{$rs->{label}}) {
	    $numfound++ unless $rsfound{$rs->{label}};
	    $rsfound{$rs->{label}} = 1;
	  }
	  last if $numfound > $#REMOVED_REALSERVERS;
	}
	last if $numfound > $#REMOVED_REALSERVERS;
      }
      last if $numfound > $#REMOVED_REALSERVERS;
    }
    unless($numfound > $#REMOVED_REALSERVERS) {
      warn "Realserver labels not found in config file:\n";
      foreach my $rs (sort keys %rsfound) {
	warn(sprintf "  %s\n", $rs->{label});
      }
      exit 1;
    }
  }
  if(exists $OPT{t}) {
    $TEST = 1;
  }
  if(exists $OPT{u}) {
    if($OPT{u} and grep { $_ eq $OPT{u} } @{$CONFIG{derived}->{update_groups}}) {
      $UPDATE_GROUP = $OPT{u};
    } else {
      warn(sprintf "Unknown update group '%s'.\n", $OPT{u} || '');
      warn "Valid update groups are:\n";
      foreach my $state (@{$CONFIG{derived}->{update_groups}}) {
	warn(sprintf "%s\n", $state);
      }
      exit 1;
    }
  }
}

sub get_info {
  # Get network info: What's this machine's hostname?  What are its DNS records
  # like?  Put the results into global %INFO.
  $INFO{public}->{hostname} = hostname;
  chomp $INFO{public}->{hostname};
  foreach my $rr (dns_query 'AAAA', $INFO{public}->{hostname}) {
    next if $rr->type ne 'AAAA';
    push @{$INFO{public}->{ipv6}}, NetAddr::IP->new($rr->address());
  }
  debug_printf "This server's public IPv6 addresses: %s", (join ', ', @{$INFO{public}->{ipv6}}) if exists $INFO{public}->{ipv6};
  foreach my $rr (dns_query 'A', $INFO{public}->{hostname}) {
    next if $rr->type ne 'A';
    push @{$INFO{public}->{ipv4}}, NetAddr::IP->new($rr->address());
  }
  $INFO{private}->{hostname} = $INFO{public}->{hostname};
  $INFO{private}->{hostname} =~ s/^([^.]+).*$/$1.goc/;
  foreach my $rr (dns_query 'AAAA', $INFO{private}->{hostname}) {
    next if $rr->type ne 'AAAA';
    push @{$INFO{private}->{ipv6}}, NetAddr::IP->new($rr->address());
  }
  foreach my $rr (dns_query 'A', $INFO{private}->{hostname}) {
    next if $rr->type ne 'A';
    push @{$INFO{private}->{ipv4}}, NetAddr::IP->new($rr->address());
  }
}

sub is_disabled($) {
  # Given a RIP record of the sort contained in
  # @{$CONFIG{sync_groups}->[<m>]->{services}->[<n>]->{real_servers}}, returns
  # whether the given RIP is disabled. Ordinarily we'll only look to see
  # whether the key $rs->{disabled} exists. But, if $UPDATE_GROUP is set to
  # something nonnull and $rs->{disabled_in} exists, look to see whether
  # $UPDATE_GROUP is found in @{$rs->{disabled_in}}. If it is, return true. If
  # not, return false. There's also @REMOVED_REALSERVERS now -- if $rs->{label}
  # is in that array, return true.
  my($rs) = @_;

  # If @REMOVED_REALSERVERS is defined, see if $rs->{label} appears in that
  # array.
  if(@REMOVED_REALSERVERS) {
    my @removed_matches = grep { $_ eq $rs->{label} } @REMOVED_REALSERVERS;
    return 1 if $#removed_matches > -1;
  }

  # If $UPDATE_GROUP is defined and nonnull, see if $UPDATE_GROUP is found in
  # @{$rs->{disabled_in}}.
  if(defined $UPDATE_GROUP and $UPDATE_GROUP ne '') {
    if(exists $rs->{disabled_in} and ref $rs->{disabled_in} eq 'ARRAY') {
      my @ug_matches = grep { $_ eq $UPDATE_GROUP } @{$rs->{disabled_in}};
      return($#ug_matches > -1);
    }
  }

  # If none of that happened, just look at $rs->{disabled}.
  return(exists $rs->{disabled});
}

sub canonical($) {
  # Given a NetAddr::IP object, return a string containing the address
  # in canonical format.  For IPv4, this just means to print each byte
  # in decimal, separated by periods.  For IPv6, this means to print
  # the 16-bit words in hex with leading zeros omitted, separated by
  # colons, hex digits a-f are lowercase, and the longest run of zero
  # words is collapsed into ::.  Returns undef if the argument isn't a
  # NetAddr::IP object, or if the IP version isn't 4 or 6 (coders of
  # the future, please add more elsif stanzas when new IP versions are
  # developed).
  my($ip) = @_;
  return undef unless ref($ip) eq 'NetAddr::IP';
  if($ip->version() eq 4) {
    # The addr method works great for IPv4, but for IPv6 it prints all
    # the zero words (2001:18e8:2:6::1 becomes 2001:18E8:2:6:0:0:0:1).
    return $ip->addr();
  } elsif($ip->version() eq 6) {
    # The short method works great for IPv6 apart from rendering A-F
    # in uppercase, but in the IPv4 case it squashes two interior zero
    # bytes to nothing (1.0.0.2 becomes 1.2, but 0.1.2.3, 1.0.2.3,
    # 1.2.0.3, and 1.2.3.0 are left alone, as are 0.0.1.2 and 1.2.0.0
    # -- this is bad for 127.0.0.1).  I don't know why it's written
    # that way.
    return lc($ip->short());
  } else {
    return undef;
  }
}

sub init {
  # Do any initialization tasks that might need to be done.
  $Storable::canonical = 1;
  read_config;
  handle_options;
  get_info;
#  process_exceptions;
}

sub write_firewall_config {
  # Write $FW_LVS_HOSTDATA based on %CONFIG.
  if($TEST) {
    test_printf 'Writing %s.', $FW_LVS_HOSTDATA;
    return 1;
  }
  my $fh = IO::File->new(">$FW_LVS_HOSTDATA");
  unless($fh) {
    warn "Error: Unable to write to $FW_LVS_HOSTDATA: $!\n";
    return '';
  }
  $fh->printf("# Written by goc_lvs.pl.  Do not edit.\n\n");
  $fh->printf("LVS_HOSTDATA=(\n");
  foreach my $sg (@{$CONFIG{sync_groups}}) {
    foreach my $service (@{$sg->{services}}) {
      my @proto_port_strings = ();
      foreach my $proto_string (split /;/, $service->{forward}) {
	my($proto, $port_ranges_string) = split m!/!, $proto_string;
	my @port_ranges = split /,/, $port_ranges_string;
	push @proto_port_strings,
	  map {
	    $_ = '0' if $_ eq '*';
	    sprintf '%s:%s', lc $proto, $_
	  } @port_ranges;
      }
      $fh->printf("    \"%s %s\"\n",
		  $service->{label},
		  join(' ', @proto_port_strings));
    }
  }
  $fh->printf(")\n");
  $fh->close();
  return 1;
}

sub write_lvs_config {
  # Write $LVS_CONFIG based on %CONFIG.
  if($TEST) {
    test_printf 'Writing %s.', $LVS_CONFIG;
    return 1;
  }
  my $fh = IO::File->new(">$LVS_CONFIG");
  unless($fh) {
    warn "Error: Unable to write to $LVS_CONFIG: $!\n";
    return '';
  }
  $fh->printf(<<"EOF");
! Configuration file for keepalived -- written by goc_lvs.pl -- do not edit

global_defs {
    notification_email {
EOF
  ;
  foreach my $email_to (@{$CONFIG{globals}->{email_to}}) {
    $fh->printf("        %s\n", $email_to);
  }
  # It is annoying and confusing that there are VRRP instances, and then there
  # are individual keepalived instances of each VRRP instance.  I'm going to
  # call VRRP instances "virtual routers" or "vrouters", and I'm going to call
  # keepalived instances of these virtual routers by the completely
  # unprecedented and made-up term "subinstances" or "subinsts".  Anyway, we
  # now have to figure out which subinstance this script is running on.
  my $this_subinst = undef;
  foreach my $sg (@{$CONFIG{sync_groups}}) {
    foreach my $subinst (@{$sg->{instances}}) {
#      printf "'%s' ? '%s' || '%s'\n", $subinst->{hostname}, $INFO{public}->{hostname}, $INFO{private}->{hostname};
      if($subinst->{hostname} eq $INFO{public}->{hostname}
	 or $subinst->{hostname} eq $INFO{private}->{hostname}) {
	$this_subinst = $subinst;
	last;
      }
    }
  }
  unless(defined $this_subinst) {
    warn "Unable to determine which LVS instance this is!\n";
    exit 1;
  }
  my $router_id = $this_subinst->{label};
  $fh->print(<<"EOF");
    }
    notification_email_from $CONFIG{globals}->{email_from}
    smtp_server $CONFIG{globals}->{smtp_server}
    smtp_connect_timeout $CONFIG{globals}->{smtp_connect_timeout}
    router_id $router_id
}
EOF
  ;
  foreach my $sg (@{$CONFIG{sync_groups}}) {
    my $current_vrouter = 0;
    my @vrouter_services = ([]);
    my $current_vrouter_vips = 0;
    # Go through the list of services and assign services to VRRP instances.
    foreach my $service (sort { $a->{label} cmp $b->{label} } @{$sg->{services}}) {
      $service->{vips} = [];
      # Look up the virtual IP's hostname as both A and AAAA; ignore CNAMES
      # here
      my $svclabel = $service->{label};
      foreach my $type ('A', 'AAAA') {
	next if $type eq 'A' and exists $service->{noipv4};
	next if $type eq 'AAAA' and exists $service->{noipv6};
	push @{$service->{vips}},
	  map { NetAddr::IP->new($_->address()) }
	    grep { $_->type ne 'CNAME' } dns_query $type, $service->{vip};
      }
      if($current_vrouter_vips + scalar(@{$service->{vips}}) > $MAX_VIPS) {
	# This means that if we added this service's VIPs to the current
	# instance, we would have more than $MAX_VIPS VIPs in the instance,
	# which would cause problems, so don't do that -- start a new instance
	# and add them to that one instead.
	++$current_vrouter;
	$vrouter_services[$current_vrouter] = [];
	$current_vrouter_vips = 0;
      }
      # If we just started a new instance, this will add the service to that
      # one.  If not, this will add it to the current instance we've got going.
      push @{$vrouter_services[$current_vrouter]}, $service;
      $current_vrouter_vips += scalar(@{$service->{vips}});
    }
    # Print code defining the sync group, now that we know how many instances
    # it will have.
    $fh->print(<<"EOF");

vrrp_sync_group $sg->{label} {
    group {
EOF
    ;
    for(my $i = 0; $i < scalar(@vrouter_services); ++$i) {
      my $vrouter_name = sprintf '%s_%X', $router_id, $i;
      $fh->printf("        %s\n", $vrouter_name);
    }
    $fh->print(<<"EOF");
    }
}
EOF
    ;
    # Print code defining each instance.
    my $vrouter_id = $sg->{id};
    for(my $i = 0; $i < scalar(@vrouter_services); ++$i) {
      my $vrouter_name = sprintf '%s_%X', $router_id, $i;
      my $authtype = ($sg->{auth_type} eq 'password')?'PASS':'(unknown)';
      $fh->printf(<<"EOF");

vrrp_instance $vrouter_name {
    state $this_subinst->{state}
    interface eth0
    virtual_router_id $vrouter_id
    priority $this_subinst->{priority}
    advert_int $sg->{advert_int}
    authentication {
        auth_type $authtype
        auth_pass $sg->{auth_pass}
    }
    virtual_ipaddress {
EOF
      ;
      foreach my $service (@{$vrouter_services[$i]}) {
	$fh->printf(<<"EOF");
        # $service->{vip}
EOF
	;
	foreach my $vip (@{$service->{vips}}) {
	  my $ip_vip = NetAddr::IP->new($vip);
	  my $canon_vip = canonical $ip_vip;
	  $fh->printf(<<"EOF");
        $canon_vip
EOF
;
	}
      }
      $fh->printf(<<"EOF");
    }
}
EOF
      ;
      ++$vrouter_id;
    }
  }

  # Now we need one virtual_server section for each VIP and port.
  foreach my $sg (@{$CONFIG{sync_groups}}) {
    foreach my $service (sort { $a->{label} cmp $b->{label} } @{$sg->{services}}) {
      # The short hostname, for comments
      my($short) = split /\./, $service->{vip}, 2;
      foreach my $proto_string (split /;/, $service->{forward}) {
	my($proto, $port_ranges_string) = split m!/!, $proto_string;
	my @port_ranges = split /,/, $port_ranges_string;
	$fh->printf(<<"EOF");

###############################################################################
# $service->{label}
###############################################################################
EOF
	;
	foreach my $vip (@{$service->{vips}}) {
	  # IP version of address (4/6)
	  my $ipv = $vip->version();
	  my $canon_vip = canonical $vip;
	  foreach my $port_range (@port_ranges) {
	    # The real server and port range string, for the comment
	    my $real_server_string = join(',', map {
	      sprintf '%s/%s', $_->{label}, $port_range
	    } @{$service->{real_servers}});
	    # The port: change '*' to 0
	    my $port = $port_range;
	    if($port eq '*') {
	      $port = '0';
	    }
	    $fh->printf(<<"EOF");

# v$ipv: $short/$port_range -> $real_server_string

virtual_server $canon_vip $port {	# $service->{vip}
    delay_loop $service->{delay_loop}
    lb_algo $service->{lb_algo}
    lb_kind $service->{lb_kind}
    persistence_timeout $service->{persistence_timeout}
    protocol $proto
EOF
	    ;
	    foreach my $real_server (@{$service->{real_servers}}) {
	      # We're going to count the real_server enabled unless it has a
	      # "disabled" key that exists (the value is unimportant).
#	      next if exists $real_server->{disabled};
	      next if is_disabled $real_server;
	      # Look for a 'forward_except' key and see if we are currently
	      # matching it -- if so, skip this section.
	      my $match = '';
	      if(exists($real_server->{forward_except})) {
		foreach my $ex_proto_string (split(/;/, $real_server->{forward_except})) {
		  my($ex_proto, $ex_port_ranges_string) = split(m!/!, $ex_proto_string);
		  next unless $ex_proto eq $proto;
		  foreach my $ex_port_range (split(/,/, $ex_port_ranges_string)) {
		    if($ex_port_range eq $port_range) {
		      $match = 1;
		      last;
		    }
		  }
		  last if $match;
		}
	      }
	      next if $match;
	      # Look up the IP for $real_server->{rip} (yes, I know it's a
	      # hostname and not actually an RIP)
	      my $type = ($ipv == 6)?'AAAA':'A';
	      my @rips = map { NetAddr::IP->new($_->address()) }
		grep { $_->type ne 'CNAME' } dns_query $type, $real_server->{rip};
	      if($#rips > -1) {
		my $canon_rip = canonical $rips[0];
		$fh->printf(<<"EOF");
    real_server $canon_rip $port {	# $real_server->{rip}
        weight $real_server->{weight}
EOF
		;
		# See if we're checking the real_servers for this service.
		if($service->{check}) {
		  # $vlan will be 'public' or 'private' (or '' if
		  # there's a configuration error)
		  my $vlan = '';
		  while(my($each_vlan, $each_pfx) = each %PREFIX) {
		    printf "Does %s contain %s? ", lc($each_pfx->{'ipv'.$ipv}), (canonical $rips[0]) if $DEBUG;
		    if($each_pfx->{'ipv'.$ipv}->contains($rips[0])) {
		      print "Yes\n" if $DEBUG;
		      $vlan = $each_vlan;
		      last;
		    } else {
		      print "No\n" if $DEBUG;
		    }
		  }
		  keys %PREFIX;	# Resets the 'each'
		  printf "\$vlan = %s\n", $vlan if $DEBUG;
		  warn "Configuration error; unable to determine whether public or private VLAN" if $vlan eq '';
		  my $bindto = canonical $INFO{$vlan}->{'ipv'.$ipv}->[0];
		  if($DEBUG and !defined $bindto) {
		    print "DEBUG: \$bindto not defined!\n";
		    printf "DEBUG: \$ipv = '%s'; \$vlan = '%s'; \n", $ipv, $vlan;
		  }
		  $fh->printf(<<"EOF");
        $service->{check}->{type} {
            connect_port $service->{check}->{connect_port}
            connect_timeout $service->{check}->{connect_timeout}
            bindto $bindto
        }
EOF
		  ;
		}
		$fh->printf(<<"EOF");
    }
EOF
		;
	      }
	    } # foreach $real_server
	    $fh->printf(<<"EOF");
}
EOF
	    ;
	  } # foreach $port_range
	} # foreach $vip
      } # foreach $proto_string
    } # foreach $service
  } # foreach $sg
  $fh->close();
  return 1;
}

sub has_systemd {
  # Return true if the system has systemd and false if it doesn't.  The
  # assumption is still that it's an RPM-using Red Hat family distro.
  if(((system '/bin/rpm -q systemd >/dev/null') >> 8) == 0) {
    return 1;
  } else {
    return '';
  }
}

sub service_exists($) {
  # Return true if the given service exists (is defined on the system,
  # regardless of whether it is active or not), and false if it doesn't.  Keep
  # systemd in mind.

  my($service) = @_;
  if(((system "/bin/rpm -q $service >/dev/null") >> 8) == 0) {
    return 1;
  } else {
    return '';
  }
}

sub restart_service($) {
  # Run a try-restart or condrestart on the given service.  Assumes that the
  # service supports try-restart (under systemd) or condrestart (under SysV).

  my($service) = @_;
  if(has_systemd) {
    system "systemctl try-restart ${service}.service";
  } else {
    system "service $service condrestart";
  }
}

sub restart_services() {
  # Restart services.  Check to see whether they're running first.

  if($TEST) {
    test_printf 'Restarting services.';
    return 1;
  }
  # First restart iptables.  Look to see whether there's a gociptables, and use
  # that if it exists.
  if(service_exists 'gociptables') {
    restart_service 'gociptables';
  } else {
    restart_service 'iptables';
  }

  # Restart keepalived
  restart_service 'keepalived';
}

###############################################################################
# Main Program
###############################################################################

init;
#if($DEBUG) {
#  use Data::Dumper;
#  print Dumper(\%CONFIG);
#}
write_firewall_config;
write_lvs_config;
restart_services;
