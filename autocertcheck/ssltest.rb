#!/usr/bin/env ruby

# ssltest.rb -- Tom Lee <thomlee@iu.edu>
# Written on or about 2017-04-13

# This is a script mostly to illustrate how to do various OpenSSL-related tasks
# in Ruby. Some of these are things that weren't well documented, and I had to
# dig and experiment to figure them out. Basically, give the script a file and
# it will try to figure out what the file is and print some information about
# it. Currently it can read .p12 files and .pem files, and within those files
# it can handle certificates, certificate requests, and unencrypted RSA
# keys. It can handle encrypted .p12 files.

require 'openssl'
require 'set'

path = ARGV[0]
if path.nil?
  STDERR.puts "Please give the path to a file as an argument."
  abort
end

class OpenSSL::PKey::RSA
  # Extra methods for keys.

  public

  def fingerprint
    # Implement a fingerprint method for keys so they can be easily compared.
    return ((OpenSSL::Digest::SHA256.new.digest self.to_der).unpack 'H*').join ''
  end
end

class OpenSSL::X509::Certificate
  # Extra methods for X.509 certificates.

  def fingerprint
    # Returns a fingerprint for the certificate's public key.
    return self.public_key.fingerprint
  end
end

def generate_nonce size = 16
  # Generate a string made of the hex representations of the given number of
  # random bytes. Used by consistency_check.
  return ((OpenSSL::Random.random_bytes size).unpack "C#{size}").map { |x| sprintf '%02X', x }.join
end

def consistency_check cert, key
  # Determine whether cert and key match cryptographically.
  nonce = generate_nonce size = 16
  pubkey = cert.public_key
  encrypted = pubkey.public_encrypt nonce
  begin
    decrypted = key.private_decrypt encrypted
  rescue OpenSSL::PKey::RSAError => e
    if e.message == 'padding check failed'
      return false
    end
    raise e
  end
  return decrypted == nonce
end

def extract_sans exts
  # Given an array of OpenSSL::X509::Extension objects, extract any
  # subjectAltNames.
  sans = []
  exts.select do |ext|
    ext.oid == 'subjectAltName'
  end.each do |ext|
    sans += ext.value.split /\s*,\s*/
  end
  return sans.sort
end

def pretty_print_key key = nil, prefix = nil
  # Prints salient data about a key in some consistent and readable
  # format. Prepends a prefix if one is given.
  keys = %w(Fingerprint Exponent Size)
  data = {
    'Fingerprint' => key.fingerprint,
    'Exponent' => key.params['e'].to_i,
    'Size' => key.params['n'].num_bits,
  }
  pfx = ''
  pfx = prefix if prefix
  keys.each do |k|
    puts "#{prefix} #{k}: #{data[k]}"
  end
end

def pretty_print_cert cert = nil, prefix = nil
  keys = [
          'Subject',
          'Issuer',
          'Not Before',
          'Expires',
          'Signature Algorithm',
          ]
  data = {
    'Subject' => cert.subject,
    'Issuer' => cert.issuer,
    'Not Before' => cert.not_before,
    'Expires' => cert.not_after,
    'Signature Algorithm' => cert.signature_algorithm,
  }
  keys.each do |k|
    puts "#{prefix} #{k}: #{data[k]}"
  end
  sans = extract_sans cert.extensions
  if sans.size > 0
    puts "#{prefix} Alternative Names: #{sans.join ', '}"
  end
  pretty_print_key cert.public_key, "    #{prefix} Public Key"
end

def pretty_print_csr csr = nil, prefix = nil
  keys = [
          'Subject',
          'Signature Algorithm',
          ]
  data = {
    'Subject' => csr.subject,
    'Signature Algorithm' => csr.signature_algorithm,
  }
  keys.each do |k|
    puts "#{prefix} #{k}: #{data[k]}"
  end
  # To get the SANs from a CSR, we'll have to first get any extensions it's
  # got. In a CSR, they're stored as "Extension Request" ("extReq") attributes.
  extensions = []
  # Each 'extReq' attribute contains an ASN1 SET, which contains an array of
  # ASN1 SEQUENCES, the first of which contains an array of X.509
  # extensions. Anyway, first see if there are any attributes with OID
  # "extReq". If there are any extReq attributes, get the extensions from
  # within them.
  csr.attributes.select do |att|
    att.oid == 'extReq'
  end.each do |extreq|
    extreq.value.entries.each do |seq|
      seq.map do |extseq|
        extensions.push(OpenSSL::X509::Extension.new extseq)
      end
    end
  end
  sans = extract_sans extensions
  if sans.size > 0
    puts "#{prefix} Alternative Names: #{sans.join ', '}"
  end
  pretty_print_key(csr.public_key, "    #{prefix} Public Key")
end

###############################################################################
# Main
###############################################################################

# Decide what type of file we have and do something with it, usually involving
# reading from it.

# How to read a PKCS#12 file:
if path.end_with? '.p12'
  # Read the raw data from the .p12 file.
  contents = File.read path
  # Set this flag to false.
  good_password = false
  # Repeat until the password is correct.
  until good_password
    begin
      # Get a password.
      system 'stty -echo'
      print "Enter decryption password for #{File.basename path}: "
      password = STDIN.gets.chomp
      system 'stty echo'
      puts
      # Try the password (may cause an exception, which is why this is inside
      # begin...rescue statements).
      p12 = OpenSSL::PKCS12.new contents, password
    rescue OpenSSL::PKCS12::PKCS12Error
      # The password caused an exception.
      puts "Incorrect password"
    rescue
      # Some other exception happened. Just raise it.
      raise
    else
      # No exception occurred -- set good_password to true so we can move on.
      good_password = true
    end
  end

  cacerts = p12.ca_certs
  if cacerts
    cacerts.each do |cacert|
      puts
      pretty_print_cert cacert, 'CA Certificate'
    end
  else
    puts '(No CA certs in file)'
  end

  cert = p12.certificate
  if cert
    puts
    pretty_print_cert cert, 'Certificate'
  else
    puts '(No certificate in file)'
  end

  key = p12.key
  if key
    puts
    pretty_print_key key, 'Private Key'
  else
    puts '(No private key in file)'
  end

  if consistency_check cert, key
    puts 'Public and private keys are consistent'
  else
    puts 'Public and private keys are NOT consistent'
  end

elsif path.end_with? '.pem'
  # Could be a cert, key, or CSR.
  filedata = File.read path
  re = %r{(-----BEGIN ([^-]+)-----[a-zA-Z0-9+/=\012]+-----END \2-----)}m
  filedata.scan(re) do |marr|
    pemdata = marr[0]
    puts "#{marr[1]} detected."
    if pemdata.include? '-----BEGIN CERTIFICATE-----'
      cert = OpenSSL::X509::Certificate.new pemdata
      puts
      pretty_print_cert cert, 'Certificate'
    elsif pemdata.start_with? '-----BEGIN CERTIFICATE REQUEST-----'
      csr = OpenSSL::X509::Request.new pemdata
      puts
      pretty_print_csr csr, 'Certificate Request'
    elsif pemdata.start_with? '-----BEGIN RSA PRIVATE KEY-----'
      key = OpenSSL::PKey::RSA.new pemdata
      puts
      pretty_print_key key, 'Key'
    else
      puts "I don't know how to handle a #{marr[1]} at present."
    end
  end
else
  puts "I don't know how to handle files with that extension."
end
