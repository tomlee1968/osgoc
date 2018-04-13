#!/usr/bin/env ruby

require 'openssl'

# Ruby 1.9.3 introduced the File.write method; fake it if we have an earlier Ruby.
unless File.respond_to? :write
  class File
    def File.write path, data
      File.open(path, mode = "w") do |file|
        file.write data
      end
    end
  end
end

# Set your CN and SANs here, or use a different means of importing them if you prefer.
cn = "myserv.grid.iu.edu"
sans = %w(DNS:myserv.opensciencegrid.org DNS:myserv1.grid.iu.edu DNS:myserv2.grid.iu.edu)

# Create key and CSR objects.
key = OpenSSL::PKey::RSA.new 2048
csr = OpenSSL::X509::Request.new

# Write private key to file.
File.write "./#{cn}_key.pem", key.to_pem


# Set parameters on CSR object.
csr.version = 0
csr.subject = OpenSSL::X509::Name.parse "/C=US/ST=Indiana/L=Bloomington/O=Indiana University/OU=Open Science Grid Operations Center/CN=#{cn}"
csr.public_key = key.public_key

# Add SANs, if any, to CSR object. Will skip without errors if sans is undefined, nil, anything that isn't an array, or empty.
if defined? sans and sans.respond_to? :size and sans.respond_to? :join and sans.size > 0
  sanstring = sans.join ', '
  extfact = OpenSSL::X509::ExtensionFactory.new
  sanext = extfact.create_extension 'subjectAltName', sanstring, false
  sanseq = OpenSSL::ASN1::Sequence.new [sanext]
  sanset = OpenSSL::ASN1::Set.new [sanseq]
  sanatt = OpenSSL::X509::Attribute.new 'extReq', sanset
  csr.add_attribute sanatt
end

# Sign CSR object.
csr.sign key, OpenSSL::Digest::SHA512.new

# Write CSR to file.
File.write "./#{cn}_csr.pem", csr.to_pem
