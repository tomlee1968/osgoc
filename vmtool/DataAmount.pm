package DataAmount;

use bignum;
use strict;
use warnings;
use overload
  '+' => \&add,
  '-' => \&subtract,
  '*' => \&multiply,
  'bool' => \&bool,
  '0+' => \&bytes,
  '""' => \&bytes;

$DataAmount::VERSION = '1.0';

=head1 NAME

DataAmount - Utility package for handling memory and disk sizes with IEEE1541
units

=head1 SYNOPSIS

my $da = DataAmount->new('540 GB');
print $da->bytes(), "\n";
print $da->in('MiB'), "\n";

=head1 DESCRIPTION

This module is able to parse number-unit strings representing a quantity of
bytes, storing them internally as a pure number of bytes, manipulates these
quantities mathematically, and output this in any unit desired.

The units supported are:

   B (byte)     =                         1 byte  = 10^0  bytes
  kB (kilobyte) =                     1,000 bytes = 10^3  bytes
  MB (megabyte) =                 1,000,000 bytes = 10^6  bytes
  GB (gigabyte) =             1,000,000,000 bytes = 10^9  bytes
  TB (terabyte) =         1,000,000,000,000 bytes = 10^12 bytes
  PB (petabyte) =     1,000,000,000,000,000 bytes = 10^15 bytes
  EB (exabyte)  = 1,000,000,000,000,000,000 bytes = 10^18 bytes
   B (byte)     =                         1 byte  = 2^0   bytes
 kiB (kibibyte) =                     1,024 bytes = 2^10  bytes
 MiB (mebibyte) =                 1,048,576 bytes = 2^20  bytes
 GiB (gibibyte) =             1,073,741,824 bytes = 2^30  bytes
 TiB (tebibyte) =         1,099,511,627,776 bytes = 2^40  bytes
 PiB (pebibyte) =     1,125,899,906,842,624 bytes = 2^50  bytes
 EiB (exbibyte) = 1,152,921,504,606,846,976 bytes = 2^60  bytes

The module is also able to handle ZB (zettabytes, 10^21 B), YB (yottabytes,
10^24 B), ZiB (zetbibytes, 2^70 B), and YiB (yotbibytes, 2^80 B).

What's more, this module can handle "LVM units," which is what I'm calling the
single-character units used by the Logical Volume Manager's commands.  These
are:

 k = kB    K = kiB
 m = MB    M = MiB
 g = GB    G = GiB
 etc.      etc.

To let you in on a little secret, the IEEE1541 units are case-insensitive,
because they're unambiguous.  LVM units, however, are case-sensitive.  This
module does NOT distinguish between "b" and "B", even though "b" is usually an
abbreviation for bits -- this module doesn't handle data on a bit level.

=cut

my(%SINGLE) =
  (
   Y => 'yib',
   Z => 'zib',
   E => 'eib',
   P => 'pib',
   T => 'tib',
   G => 'gib',
   M => 'mib',
   K => 'kib',
   y => 'yb',
   z => 'zb',
   e => 'eb',
   p => 'pb',
   t => 'tb',
   g => 'gb',
   m => 'mb',
   k => 'kb',
  );
my(%RSINGLE) = reverse %SINGLE;
my(%MULT) =
  (
   yib => 1208925819614629174706176,
   zib => 1180591620717411303424,
   eib => 1152921504606846976,
   pib => 1125899906842624,
   tib => 1099511627776,
   gib => 1073741824,
   mib => 1048576,
   kib => 1024,
   yb  => 1000000000000000000000000,
   zb  => 1000000000000000000000,
   eb  => 1000000000000000000,
   pb  => 1000000000000000,
   tb  => 1000000000000,
   gb  => 1000000000,
   mb  => 1000000,
   kb  => 1000,
   b   => 1,
  );

=head1 FUNCTIONS

=over 4

=cut

=item DataAmount->new([$string]);

Defines a new DataAmount object.  If $string is supplied, it also parses that
string and initializes the object to that new value.

=cut

sub new($$) {
  my($class, $string) = @_;
  my $value = undef;
  my $self = \$value;
  $$self = iparse($string) if $string;
  return bless $self, $class;
}

=item $da->parse($string);

Parses a string, storing the data amount within $da and replacing whatever
value $da had previously.  The value of $string is intended to be some
numerical value followed by an optional space and then an optional unit
specifier.  If no units are specified, units of bytes are assumed.  If this
routine can't parse $string, $da will be an undefined value.

=cut

sub iparse($) {
  my($string) = @_;

  # Squish initial and final spaces.
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  # For units, accept any of:
  # k (or mgtpeyz)
  # K (or MGTPEYZ)
  # kB (or MB, etc.)
  # kiB (or MiB, etc.)
  # B
  # Nothing (= B)
  my($bytes, $number, $unit);
  if($string =~ /[kmgtpeyz]ib$/i) {
    ($number, $unit) = ($string =~ /^(.*?)\s*([kmgtpeyz]ib)$/i);
    $bytes = $number*$MULT{lc($unit)};
  } elsif($string =~ /[kmgtpeyz]b$/i) {
    ($number, $unit) = ($string =~ /^(.*?)\s*([kmgtpeyz]b)$/i);
    $bytes = $number*$MULT{lc($unit)};
  } elsif($string =~ /[kmgtpeyz]$/i) {
    ($number, $unit) = ($string =~ /^(.*?)\s*([kmgtpeyz])$/i);
    $bytes = $number*$MULT{$SINGLE{$unit}};
  } elsif($string =~ /\d\s*b$/i) {
    ($number, $unit) = ($string =~ /^(.*?)\s*(b)$/i);
    $bytes = $number*1;
  } elsif($string =~ /\d$/) {
    $number = $string*1;
    $unit = 'B';
    $bytes = $number*1;
  } else {
    warn("Cannot parse '$string'\n");
    return undef;
  }
#  printf("'%s' = '%s' '%s'\n", $bytes, $number, $unit);
  return $bytes;
}

sub parse(\$$) {
  my($self, $string) = @_;
  $$self = iparse($string);
  return $self;
}

=item $da->bytes();

Returns the raw number of bytes in $da.  If $da hasn't been initialized via
new() or parse(), returns an undefined value.  Return value will be a pure
number, unlike the base2() and base10() methods.

=cut

sub bytes(\$) {
  my($self) = @_;
  return undef unless defined($$self);
  return $$self || 0;
}

=item $da->in($unit);

Returns the data amount in the given unit.  Return value will be a pure number,
unlike in_unit().

=cut

sub in(\$$) {
  my($self, $unit) = @_;
  return undef unless defined($$self);
  my $oneunit = iparse("1 $unit");
  return $$self/$oneunit;
}

=item $da->in_unit($unit[, $nospace]);

Returns the data amount in the given unit, in printable form with the given
unit appended.  Return value will be a string consisting of the number and unit
abbreviation, with a space between.  If $nospace is present and nonzero, there
will be no space.  Other than $nospace, this is the equivalent of

  sprintf('%g %s', $da->in($unit), $unit);

=cut

sub in_unit(\$$$) {
  my($self, $unit, $nospace) = @_;
  return undef unless defined($$self);
  my $oneunit = iparse("1 $unit");
  my $space = (defined($nospace) && $nospace)?'':' ';
  return sprintf('%g%s%s', $$self/$oneunit, $space, $unit);
}

=item $da->min_base10_unit()

Returns the minimal powers-of-10 (SI) unit (kB, MB, GB, etc.) that $da can be
expressed in without being all fractional.  This will be a string, the unit's
abbreviation.  As with most other routines, this will return undefined if $da
hasn't been initialized or is a result from an unparseable input string.

=cut

sub min_base10_unit(\$) {
  my($self) = @_;
  return undef unless defined($$self);
  my $unit = undef;
  foreach my $un (qw(YB ZB EB PB TB GB MB kB)) {
    if($MULT{lc($un)} <= $$self) {
      $unit = $un;
      last;
    }
  }
  unless(defined($unit)) {
    warn("Unable to find a minimal base-10 unit for $$self.  Odd.\n");
    return undef;
  }
  return $unit;
}

=item $da->min_base10_unit_lvm()

Returns the minimal powers-of-10 LVM unit (k, m, g, etc.) that $da can be
expressed in without being all fractional.  This is the same as
min_base10_unit(), only the result is expressed in LVM units.

=cut

sub min_base10_unit_lvm(\$) {
  my($self) = @_;
  return undef unless defined($$self);
  my $unit = &min_base10_unit($self);
  return undef unless defined($unit);
  return $RSINGLE{lc($unit)};
}

=item $da->in_min_base10_unit([$nospace])

Returns the value of $da expressed in the minimal powers-of-10 (SI) unit (kB,
MB, GB, etc.) that it can be expressed in without being all fractional.  This
will be a string consisting of a number, a space, and the unit abbreviation.
$nospace, if present and true, suppresses that space.  This is the equivalent
of

  $da->in_unit($da->min_base10_unit(), $nospace);

=cut

sub in_min_base10_unit(\$$) {
  my($self, $nospace) = @_;
  return undef unless defined($$self);
  my $unit = &min_base10_unit($self);
  return undef unless defined($unit);
  return &in_unit($self, $unit, $nospace);
}

=item $da->in_min_base10_unit_lvm([$nospace])

Returns the value of $da expressed in the minimal powers-of-10 LVM unit (k, m,
g, etc.) that it can be expressed in without being all fractional.  This is the
same as in_min_base10(), only the result is expressed in LVM units.  This is
the equivalent of

  $da->in_unit($da->min_base10_unit_lvm(), $nospace);

=cut

sub in_min_base10_unit_lvm(\$$) {
  my($self, $nospace) = @_;
  return undef unless defined($$self);
  my $unit = &min_base10_unit_lvm($self);
  return undef unless defined($unit);
  return &in_unit($self, $unit, $nospace);
}

=item $da->min_base2_unit()

Returns the minimal powers-of-2 unit (kiB, MiB, GiB, etc.) that $da can be
expressed in without being all fractional.  This will be a string, the unit's
abbreviation.

=cut

sub min_base2_unit(\%) {
  my($self) = @_;
  return undef unless defined($$self);
  my $unit = undef;
  foreach my $un (qw(YiB ZiB EiB PiB TiB GiB MiB kiB)) {
    if($MULT{lc($un)} <= $$self) {
      $unit = $un;
      last;
    }
  }
  unless(defined($unit)) {
    warn("Unable to express $$self in base-2.  Odd.\n");
    return undef;
  }
  return $unit;
}

=item $da->min_base2_unit_lvm()

Returns the minimal powers-of-2 LVM unit (K, M, G, etc.) that it can be
expressed in without being all fractional.  This is the same as
min_base2_unit(), only in LVM units.

=cut

sub min_base2_unit_lvm(\$) {
  my($self) = @_;
  return undef unless defined($$self);
  my $unit = &min_base2_unit($self);
  return undef unless defined($unit);
  return $RSINGLE{lc($unit)};
}

=item $da->in_min_base2_unit([$nospace])

Returns the value of $da expressed in the minimal powers-of-2 unit (kiB, MiB,
GiB, etc.) that it can be expressed in without being all fractional.  This will
be a string consisting of a number, a space, and the unit abbreviation.
$nospace, if present and true, suppresses that space.  This is the equivalent
of

  $da->in_unit($da->min_base2_unit(), $nospace);

=cut

sub in_min_base2_unit(\$$) {
  my($self, $nospace) = @_;
  return undef unless defined($$self);
  my $unit = &min_base2_unit($self);
  return undef unless defined($unit);
  return &in_unit($self, $unit, $nospace);
}

=item $da->in_min_base2_unit_lvm([$nospace])

Returns the value of $da expressed in the minimal powers-of-2 LVM unit (K, M,
G, etc.) that it can be expressed in without being all fractional.  This is the
same as in_min_base2(), only the result is expressed in LVM units.  This is
the equivalent of

  $da->in_unit($da->min_base2_unit_lvm(), $nospace);

=cut

sub in_min_base2_unit_lvm(\$$) {
  my($self, $nospace) = @_;
  return undef unless defined($$self);
  my $unit = &min_base2_unit_lvm($self);
  return undef unless defined($unit);
  return &in_unit($self, $unit, $nospace);
}

################################################################################
# Overloading
###############################################################################

sub add(@) {
  my($self, $other, $swap) = @_;
  my $n1 = $self->bytes();
  my $n2 = ref($other)?$other->bytes():$other;
  my $result = $n1 + $n2;
  return bless \$result;
}

sub subtract(@) {
  my($self, $other, $swap) = @_;
  my $n1 = $self->bytes();
  my $n2 = ref($other)?$other->bytes():$other;
  my $result = $n1 - $n2;
  $result = -$result if $swap;
  return bless \$result;
}

sub multiply(@) {
  my($self, $other, $swap) = @_;
  my $n1 = $self->bytes();
  my $n2 = ref($other)?$other->bytes():$other;
  my $result = $n1 * $n2;
  return bless \$result;
}

sub bool(@) {
  my($self) = @_;
  my $result;
  if($$self == 0) {
    $result = '';
  } else {
    $result = 1;
  }
  return $result;
}

=back

=head1 BUGS

I fix them when I find them.  If you find any, let me know!

=head1 AUTHORS

Thomas Lee <thomlee@iu.edu>

=cut

1;
