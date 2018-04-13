#!/usr/bin/perl

use strict;
use Crypt::OpenSSL::PKCS10;
use Crypt::OpenSSL::RSA;
use Crypt::OpenSSL::X509;
use IO::File;

# Set your CN and SANs here, or use a different means of importing them if you prefer.
my $cn = "myserv.grid.iu.edu";
my @sans = qw(DNS:myserv.opensciencegrid.org DNS:myserv1.grid.iu.edu DNS:myserv2.grid.iu.edu);

# Create key and CSR objects.
  my $key = Crypt::OpenSSL::RSA->generate_key(2048);
my $csr = Crypt::OpenSSL::PKCS10->new_from_rsa($key);

# Write private key to file.
my $fh = IO::File->new(">./${cn}_key_p.pem");
$fh->printf("%s\n", $key->get_private_key_string());
$fh->close();

# Set parameters on CSR object.
$csr->set_subject("/C=US/ST=Indiana/L=Bloomington/O=Indiana University/OU=Open Science Grid Operations Center/CN=$cn");

# Add SANs, if any, to CSR object. Will skip without errors if sans is undefined, nil, anything that isn't an array, or an empty array.
if(defined(@sans) and scalar(@sans) > 0) {
  $csr->add_ext(Crypt::OpenSSL::PKCS10::NID_subject_alt_name, join(",", @sans));
  $csr->add_ext_final();
}

# Sign CSR object.
$csr->sign();

# Write CSR to file.
my $fh = IO::File->new(">./${cn}_csr_p.pem");
$fh->printf("%s\n", $csr->get_pem_req());
$fh->close();
