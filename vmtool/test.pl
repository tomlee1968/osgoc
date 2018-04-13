#!/usr/bin/perl -w

use strict;

# Supposing you want to use a long literal string as an argument to a function.
# How do you enter it?

sub printit() {

  my($string) = @_;
  print($string);
}

sub doit() {

  my($cmd) = @_;
  $cmd =~ s/\n/ /gm;
  system($cmd);
}

&printit("This is a long string"
	 ." stitched together"
	 ." with dot concatenation\n");

&printit("This is a long string \
with extra long lines \
and I'm escaping the linebreaks \
with backslashes\n");

&printit("This is a long string
and this time
there are just linebreaks
with no escaping\n");

&printit(<<"EOF");
This is a long string
entered as a here document
with linebreaks and everything
EOF
  ;

&doit(<<"EOF");
ls
-lha
-rt
EOF
  ;
