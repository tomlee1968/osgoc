#!/usr/bin/perl -w

use strict;
use File::Basename;

printf("\$0 = %s\n", $0);
printf("basename(\$0) = %s\n", basename($0));
if(@ARGV) {
  printf("\$ARGV[0] = %s\n", $ARGV[0]);
}
