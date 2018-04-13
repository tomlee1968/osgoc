#!/usr/bin/env perl

use strict;
use warnings;

use Carp;
use IO::File;
use Try::Tiny;

my $file = 'testfile.txt';

sub test_file_stuff(&) {
  my($sub) = @_;
  my @retval = ();
  try {
    @retval = &$sub;
  } catch {
    printf STDERR "Problem: %s\n", $_;
    return undef;
  };
  return @retval;
}

my $fh = IO::File->new;
my @returns = test_file_stuff {
  $fh->open('<'.$file) || confess "Unable to open $file";
  return <$fh>;
};
print((join ', ', @returns), "\n");
printf "\$@ = '%s'\n", $@;
