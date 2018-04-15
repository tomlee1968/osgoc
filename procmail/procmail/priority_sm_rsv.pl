#!/usr/bin/perl -w

use strict;

# priority_sm_rsv.pl -- handle RSV status messages
# Tom Lee <thomlee@iu.edu>
# Begun 2013-03-25
# Last modified 2013-03-26

# Some RSV alert messages come with warnings for multiple services in
# the same email.  I'd like to filter them separately, so there's a
# procmail rule (in $HOME/.procmail/priority_sm_rsv) that pipes the
# email to this script if it's one of those.

# What this script should do is save the email's header and signature,
# take the body, break it up into one segment per host, and send one
# segment at a time through procmail again, with the original's header
# and signature (the header can be modified slightly in useful ways).

# This script should set the header 'X-TJL-Pri-SM-RSV-Seen' in any
# emails it sends back through procmail, because the rule that calls
# this script checks for that header and refuses to send the email
# through this script again if it's present.  No need for any email to
# go through this script more than once.

# A line of text with this format begins each segment of the body:

# > Mon 03/25/13 11:15:02 : OSG_Display_1 RSV status is CRITICAL : display1.grid.iu.edu

# Of course, the date and time will vary, as will the service label,
# alert level and hostname.  But it will always look like

# > (DOW) MM/DD/YY HH:MM:SS : (label) RSV status is (level) : (hostname)

# As with any script that Procmail sends an email to, the text of the
# message is piped to standard input.

# The signature is delimited from the rest of the body with "--" at
# the beginning of the line.

# Note that MUAs will think the message is the same message if the
# Message-Id header line is the same for all of them, so this script
# varies the Message-Id in a simple way.

use IO::File;
use Mail::Internet;
use Mail::Header;
use MIME::Parser;

###############################################################################
# Settings
###############################################################################

# Path to Procmail
$CFG::PROCMAIL = '/usr/bin/procmail';

# Header marker prefix
$CFG::HDRPFX = 'X-TJL-Pri-SM-RSV';

# 'Seen' header field
$CFG::HDRMARK = "${CFG::HDRPFX}-Seen";

# Objects to be the message and its header (Mail::Internet and
# Mail::Header objects)
my($m, $h);

# Arrays to be the body and signature (@b's elements will be
# references to arrays containing the lines of the segments; @s's
# elements will just be the lines of the signature)
my(@b, @s);

###############################################################################
# Subroutines
###############################################################################

sub get_mail() {
    # Read in the email.

#    $m = Mail::Internet->new(\*STDIN);
    my $p = MIME::Parser->new();
    $m = $p->parse(\*STDIN);
}

sub get_header() {
    # Get the mail's header.

    $h = $m->head();
    my $mark = $h->get($CFG::HDRMARK);
    if($mark) {
	die("We've already seen this message!\n");
    }
}

sub parse_body() {
    # Get the email's body segments and signature -- everything from a
    # line starting with "--" to the end is the signature; everything
    # before that is the body.  The body consists of segments, each
    # starting with an "RSV status is" line and not ending until
    # another such line or the signature delimiter.

    @b = ();
    @s = ();
    # This holds the lines of the current body segment:
    my @currseg = ();
    # This flags whether we're in the signature:
    my $sigflag = '';
    # Read the lines one by one
    my $bh = $m->bodyhandle->open('r');
    while(defined(my $line = $bh->getline())) {
	# If we're in the signature, put the line in @s.
	if($sigflag) {
	    push(@s, $line);
	} elsif($line =~ /^--\s*$/) {
	    # If we're looking at the sig marker, we're done with that
	    # last segment and starting the signature now.  We can't
	    # just push \@currseg onto @b, as that's a reference to an
	    # array whose contents may well change as we read in the
	    # next segment.  So push a reference to an anonymous copy
	    # of @currseg's contents onto @b.
	    push(@b, [ @currseg ]);
	    $sigflag = 1;
	    push(@s, $line);
	} elsif($line =~ m!^>\s*[a-z]{3}\s+\d\d/\d\d/\d\d\s+\d\d:\d\d:\d\d\s*:\s*.*\s+rsv\s+status\s+is\s+!i) {
	    # If we're looking at a segment header, save the previous
	    # segment if there was one (this might be the first one)
	    # and start on the new one.  As mentioned earlier, we must
	    # push a copy of @currseg's contents onto @b.
	    if(@currseg) {
		push(@b, [ @currseg ]);
	    }
	    @currseg = ($line);
	} else {
	    # Otherwise this is just a line of the current segment.
	    push(@currseg, $line);
	}
    }
}

sub init() {
    # Set things up.
    &get_mail();
    &get_header();
    &parse_body();
}

sub mark_header() {
    # Tweak the header, specifically to add a $CFG::HDRMARK header to
    # it.
    $h->replace($CFG::HDRMARK, 'yes');
}

sub tweak_header(\%$) {
    # Mark the header with specific information about this email
    my($hdr, $str, $seq) = @_;

    my($dow, $date, $time, $id, $stat, $host) =
	($str =~ m!^>\s*([a-z]{3})\s+(\d\d/\d\d/\d\d)\s+(\d\d:\d\d:\d\d)\s*:\s*([^:]+)\s+rsv\s+status\s+is\s+(\S+)\s*:\s*(\S+)!i);
    my($shorthost) = ($host =~ /^([a-z][a-z0-9-]*)/i);
    $hdr->replace("${CFG::HDRPFX}-Host", $shorthost);
    $hdr->replace("${CFG::HDRPFX}-Status", lc($stat));
    my $serv = $host;
    $serv =~ s/\..*$//;
    $serv =~ s/\d$//;
    $hdr->replace("${CFG::HDRPFX}-Service", $serv);
    $hdr->replace('Subject', sprintf('[rsvtest] [%s] [%s] RSV Alert', $shorthost, $stat));

    # MUAs think they're the same message if the Message-Id header is
    # the same.
    my $mid = $hdr->get('Message-Id');
    $mid =~ s/\@/.$seq\@/;
    $hdr->replace('Message-Id', $mid);
}

sub mail_segments() {
    # For each segment of the body, tack $h and $s onto it and pipe it
    # to procmail.

    my $seq = 1;
    foreach my $seg (@b) {
	my $hcopy = $h->dup();
	&tweak_header($hcopy, $seg->[0], $seq);
	my $newmsg = Mail::Internet->new(undef, Body => [ @$seg, @s ], Header => $hcopy);
	my $fh = IO::File->new("|$CFG::PROCMAIL") || die("Unable to open pipe to $CFG::PROCMAIL\n");
	$fh->print($newmsg->as_string());
	$fh->close();
	++$seq;
#	print($newmsg->as_string(), "\n\n");
    }
}

###############################################################################
# Main
###############################################################################

#die("Begin\n");
&init();
&mark_header();
&mail_segments();
exit(0);
