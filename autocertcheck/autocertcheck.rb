#!/usr/bin/env ruby

# autocertcheck.rb -- check certificates and install replacements
# Tom Lee <thomlee@iu.edu>
# Last modified: 2018-03-12

# This script is supposed to go through every certificate it knows about from
# its config file, which is human-edited, and make sure that each one is as it
# should be and isn't expiring. When a certificate needs to be created or
# replaced, it assists as best it can with that process. The certificates and
# keys are placed where Puppet can find them (see settings below to define
# where that is).

# This script should be located on the Puppet server that synchronizes
# certificates to the machines and locations where they go. This makes it very
# quick to check for certificate existence, upcoming expiration, correct
# CN/SAN, etc.

# The configuration file is a YAML file (see the $CONFIG global variable for
# its location) that contains information about every certificate governed by
# this script. Its structure consists of a single YAML sequence. Each element
# of the sequence is a mapping with these keys:
#
# * desc (required string): This field mostly just makes the config file easier
#   to read, but the script can also print it to help the user know what cert
#   it's currently dealing with.
#
# * type (required string): What type of certificate this is; recognized values
#   are 'internal', 'cilogon', 'digicert' (deprecated), and 'incommon'. This
#   just determines what steps the script follows to request/renew the
#   certificate.
#
# * cn (required string): The CN appearing in the certificate's subject. This
#   will be the hostname, in the case of a host cert, "service/hostname" in the
#   case of a service cert, and something else in the case of a user cert
#   (typically a username and/or email address).
#
# * san (optional sequence): The subjectAltNames for this certificate, which
#   are strings of format "<type>:<value>", where <type> can be "email", "DNS",
#   or "IP". If this appears in a host certificate, this script will
#   automatically include the hostname from the CN by default, so there's no
#   need to add it here. (If this 'san' field doesn't appear, this script won't
#   add it.)
#
# * notify (optional sequence of strings): A sequence of Puppet resources (of
#   form Type[name]) to set as the "notify" attribute for the Certificate
#   resource in Puppet. In Puppet, setting resource B in the "notify" list for
#   resource A has two effects: first, Puppet will process resource A before
#   resource B, and second, Puppet will send resource B a refresh. A refresh
#   has an effect only on Mount resources (causes them to be remounted),
#   Service resources (causes them to be restarted), and Exec resources that
#   have "refreshonly" set to true (causes them to be executed, where normally
#   they would not be). NOTE: Any resource listed here must exist! Make sure
#   the resource you're notifying is defined somewhere in the Puppet rules for
#   the target host.
#
# * msg (optional string): A note to be printed when this certificate is
#   updated, usually reminding the sysadmin of something special that must be
#   done. There are a lot of little special cases with certificates, some of
#   which this script can't handle (some of which no script could).
#
# * flags (optional mapping): A mapping consisting of optional flags that can
#   be set. They're flags, so their value is ignored; the script uses only the
#   presence (or absence) of the key. Currently the only one defined is
#   'usercert', which means this is the GOC user certificate, which is treated
#   specially. Several other flags are used internally during processing, but
#   these aren't specified in this config file.
#
# * targets (required sequence): Hosts and paths where Puppet is to install the
#   certificate. These targets are mappings. Each one has several optional
#   keys; if they are omitted, the certificate and its private key will be
#   installed according to the Operations Center standard practice. There must
#   be at least one "target". The keys for each mapping are:
#
#   - host (required string): The hostname (relative to the Puppet server) on
#     which the certificate should be installed. Different targets can have
#     different host settings, because in some cases the same certificate/key
#     can be installed on different hosts. For example, the same certificate
#     and key need to be on both repo1 and repo2, because the certificate is
#     multi-domain, and both repo1 and repo2 appear in its SAN field.
#
#   - cert (optional mapping): Specifies any nondefault details about the
#     certificate file's destination. Omitting this (or any of the details)
#     results in Puppet's placing the cert according to Operations Center
#     standard practices.
#
#   - key (optional mapping): Similar to "cert" above, only specifies details
#     about where Puppet should install the certificate's private key file. The
#     optional keys for the mappings of both "cert" and "key":
#
#     . path (optional string): The path to where in the filesystem Puppet
#       should install the cert/key. Default:
#       /etc/grid-security/<service>/cert.pem (or key.pem) (where <service> is
#       "host" for a host cert or the service in the case of service certs). If
#       "path" is set for the cert, but the key's "path" setting is a relative
#       path, that relative path is taken to be relative to the cert's
#       "path". For example, if the cert is at /path/to/cert.pem, and the key's
#       "cert" setting is "key.pem", it will be installed at
#       /path/to/key.pem. If the key's "path" setting is an absolute path, the
#       cert's "path" setting has no effect on it.
#
#     . user (optional string): The user account that should own the cert/key
#       file. Default for cert: root. Default for key: whatever the cert's
#       "user" setting is.
#
#     . group (optional string): The group that should own the cert/key
#       file. Default for cert: root. Default for key: whatever the cert's
#       "group" setting is.
#
#     . mode (optional string): The permission modes for the cert/key
#       file. Default for cert: 0644. Default for key: whatever the cert's
#       "mode" setting is, ANDed with 0700.
#
# Some examples:
#
### This would result in the cert being written to
### /etc/grid-security/host/cert.pem with mode 0644 and the key being written
### to key.pem with mode 0600 in the same directory, both with user 'root' and
### group 'root', on both foo1.goc and foo2.goc:
# - cn: foo.grid.iu.edu
#   type: cilogon
#   desc: foo host cert (CILogon)
#   targets:
#     - host: foo1.goc
#     - host: foo2.goc
#
### This would result in the cert being written to
### /etc/grid-security/http/cert.pem with mode 0644 and the key being written
### to key.pem with mode 0600 in the same directory, both with user 'apache'
### and group 'root', on both bar1.goc and bar2.goc:
# - cn: http/bar.grid.iu.edu
#   type: cilogon
#   desc: bar http cert (CILogon)
#   notify:
#     - Exec[http_condrestart]
#   targets:
#     - host: bar1.goc
#       cert:
#         user: apache
#     - host: bar2.goc
#       cert:
#         user: apache
#
### This would result in the cert being written to
### /funky/cert/path/certmadness.pem with mode 0765 and the key being written
### to /funky/cert/path/madkey.pem with mode 0700, both with user 'whoever' and
### group 'whatever', on host baz.goc:
# - cn: baz.grid.iu.edu
#   type: incommon
#   desc: baz host cert (InCommon)
#   targets:
#     - host: baz.goc
#       cert:
#         path: /funky/cert/path/certmadness.pem
#         user: whoever
#         group: whatever
#         mode: 0765
#       key:
#         path: madkey.pem
#
# Note that in the second example above, the Exec resource named
# 'http_condrestart' (presumably something that does the shell command "service
# httpd condrestart") must be defined somewhere in the Puppet rules for
# bar.goc. Note also that it is not necessary to set "user" to "apache" for
# http service certs (because Apache normally starts as root to read the key
# and then drops its privileges to an unprivileged user for security purposes);
# this is just an example.
#
# Never do anything like the last example above. You will live to regret it.
#
# A certificate's filename on the Puppet server looks like this:
#
# Host cert for foo.grid.iu.edu: foo.grid.iu.edu_cert.pem
#
# Service cert for service 'bar' on foo.grid.iu.edu: foo.grid.iu.edu_bar_cert.pem
#
# User cert for email 'foo@bar.org': foo_bar.org_user_cert.pem
#
# Key files (when they exist) have the same scheme, but with 'cert' replaced
# with 'key'.

require 'fileutils'
require 'openssl'
require 'optparse'
require 'set'
require 'tmpdir'
require 'yaml'

###############################################################################
# Settings
###############################################################################

# Version of this script
$VERSION = '0.3'

# Release of this script
$RELEASE = '1'

# Directory to find configuration in
$CONFDIR = '/home/thomlee/autocertcheck'

# Config file
$CONFIG = "#{$CONFDIR}/autocertcheck.conf.yaml"

# State file containing last status for each cert, time last checked,
# etc. (don't edit this file)
$STATEFILE = "#{$CONFDIR}/autocertcheck.state.yaml"

# Certs that expire in this many days or less will be renewed.
$EXPIRE_THRESHOLD = 30

# Progress messages will be printed no more often than this many seconds.
$PROGRESS_TIMEOUT = 5

# Certs last checked fewer than this many seconds ago won't be checked again
# unless you specify the -f option.
$RECHECK_THRESHOLD = 86400

# The base path for the Puppet development environment.
$PUPPETSRV_BASE = '/etc/puppet/env/development'

# Where on the Puppet server the certificates are found.
$PUPPETSRV_CERT_BASE = "#{$PUPPETSRV_BASE}/modules/hiera/files/certificates"

# Where on the Puppet server the Hiera global file is found.
$PUPPETSRV_HIERA_GLOBAL = "#{$PUPPETSRV_BASE}/hiera/global.yaml"

# Where on the Puppet server the Hiera host files are found.
$PUPPETSRV_HIERA_HOST_BASE = "#{$PUPPETSRV_BASE}/hiera/host"

# # GOC user certificate filename base.
$USERCERT_BASE = 'goc_opensciencegrid.org_user'

# Installation path for the GOC user certificate and its key.
$USERCERT_PATH = '/etc/grid-security/user/cert.pem'
$USERKEY_PATH = '/etc/grid-security/user/key.pem'

# The archive directory for old certs and keys.
$CERT_ARCHIVE_DIR = "#{ENV['HOME']}/old-certs"

# 2016-04-05: The osg-gridadmin-cert-request script can now handle SAN certs
# itself, but unfortunately oim.grid.iu.edu can't handle such requests. While
# we debug this issue, we have to figure out what to do for certs involving OIM
# (digicert/cilogon). This flag selects between behavior that assumes OIM works
# right and behavior that attempts to work around whatever the problem is
# today. Eventually OIM will work right, we're assuming, so this script is
# written to treat it as if it works if this flag is false.
$OIM_SAN_CERTS_BUGGED = false

# Subroutines for renewing the different types of certificates (referred to in
# CertRecord#type, where cr is a certificate record from $CONFIG)
$RENEW_TYPE =
  {
    'cilogon' => :renew_cilogon_certs,
    'digicert' => :renew_digicert_certs,
    'incommon' => :renew_incommon_certs,
    'internal' => :renew_internal_certs,
  }

# Issuer DNs for certificate types
$TYPE_ISSUER_DN =
  {
    'cilogon' => '/DC=org/DC=cilogon/C=US/O=CILogon/CN=CILogon OSG CA 1',
    'digicert' => '/DC=com/DC=DigiCert-Grid/O=DigiCert Grid/CN=DigiCert Grid CA-1',
    'doegrids' => '/DC=org/DC=DOEGrids/OU=Certificate Authorities/CN=DOEGrids CA 1',
    'incommon' => '/C=US/O=Internet2/OU=InCommon/CN=InCommon Server CA',
    'internal' => '/C=US/ST=Indiana/L=Bloomington/O=Open Science Grid/OU=Grid Operations Center/CN=OSG GOC CA',
  }

# CA certificate filenames for certificate types (must be in same directory as
# this script)
$TYPE_ISSUER_CERT =
  {
   'cilogon' => 'cilogon-osg.pem',
   'digicert' => 'DigiCertGridCA-Chain.pem',
   'doegrids' => 'DoEGridsCA-Chain.pem',
   'incommon' => 'InCommonCA-Chain.pem',
   'internal' => 'GOC_internal_CA.pem',
  }

###############################################################################
# Globals
###############################################################################

# Command-line options
$opt = {}

# Last time a progress message was printed.
$last_progress = 0

# Timestamp of start of script run.
$now = Time.new.to_i

# Digest-making object.
$digester = OpenSSL::Digest::SHA256.new

# Flag set when Ctrl-C is hit
$done = false

# Columns to erase from last progress_puts (0 if none)
$progress_columns = 0

###############################################################################
# Classes
###############################################################################

class File
  # Add a write method to the File object. There's a built-in read method but
  # not a write method.
  def File.write path, data
    File.open(path, mode = "w") do |file|
      file.write data
    end
  end
end

class Object
  def extra_true?
    # Normally Ruby considers an object "true" (that is, it will trigger an
    # "if") unless its value is nil (the only member of NilClass) or false (the
    # only member of FalseClass). This means that 0, 0.0, '', and [] are all
    # considered true values in Ruby. But this isn't always what we want, so
    # I'm adding this method.
    #
    # This method considers an object false if:
    # * Ruby would normally consider it false (i.e. it's false or nil)
    # * It has an 'empty?' method, and that method returns true (so empty
    # strings, arrays, hashes, etc. will return false)
    # * It has a 'zero?' method, and that method returns true (so 0, 0.0, 0+0j,
    # etc. will return false)
    #
    # Otherwise, it returns true. Somewhat similar to Perl's true/false
    # condition.
    #
    return false unless self    # Returns false if self is false or nil

    # Making use of duck typing: consult a "false-like" method if one exists.
    return false if self.respond_to? :empty? and self.empty?
    return false if self.respond_to? :zero? and self.zero?

    # Add more "false-like" methods if you think of them. For now, unless it's
    # been declared false already, return true.
    return true
  end

  def extra_false?
    # Just returns the Boolean opposite of extra_true?
    return !self.extra_true?
  end
end

class OpenSSL::PKey::RSA
  # Extra methods for RSA keys.

  def fingerprint
    # Implement a fingerprint method for keys so they can be easily compared.
    return (($digester.digest self.to_der).unpack 'H*').join ''
  end

  def self.new_from_file path = nil
    # It is to be expected that keys will exist only in encrypted eYAML form,
    # not in plaintext files on the server. But that is once that part of the
    # script is finished and debugged. Yeah, about that.

    return nil unless File.exist? path
#    raise FileNotFoundError.new "File '#{path}' does not exist" unless File.exist? path
    debug_puts 3, "Reading RSA key from file '#{path}'"
    return OpenSSL::PKey::RSA.new(File.read path)
  end
end

class OpenSSL::X509::Certificate
  # Extra methods for X.509 certificates.

  def expiring? threshold = 0.0
    # Returns true if the cert will expire within the given number of days
    # (default 0, meaning you're asking whether it's already expired).
    return (Time.now.to_f + threshold.to_f*86400.0) >= self.not_after.to_f
  end

  def cn
    # Returns the Common Name of the subject of the certificate. Not every
    # certificate has one; returns nil if there isn't one.
    cns = self.subject.to_a.select { |a| a[0] == 'CN' }
    return nil unless cns.size > 0
    return (cns.first)[1]
  end

  def fingerprint
    # Returns a fingerprint for the certificate's public key.
    return self.public_key.fingerprint
  end

  def self.new_from_file path = nil
    # Reads a certificate from the given file path.
    raise FileNotFoundError.new "File '#{path}' does not exist" unless File.exist? path
    debug_puts 3, "Reading X509 cert from file '#{path}'"
    return OpenSSL::X509::Certificate.new(File.read path)
  end
end

class ConfigError < RuntimeError
  # Just an extra exception class for configuration errors.
end

class FileNotFoundError < RuntimeError
end

class NoRecordError < RuntimeError
end

class FileExistsError < RuntimeError
end

class NoRemoteOutputError < RuntimeError
end

class RemoteFileError < RuntimeError
end

module CertUtils
  # Utility methods that are used in both CertLocation and CertRecord classes.

  def generate_nonce size = 16
    # Generate a string made of the hex representations of the given number of
    # random bytes.
    return ((OpenSSL::Random.random_bytes size).unpack "C#{size}").map { |x| sprintf '%02X', x }.join
  end

  def fix_yaml_input input = ''
    # Multi-line YAML data should look like this:
    #
    # foo:
    #   label: |
    #     line 1
    #     line 2
    #     line 3
    #   next_label: blah
    #
    # but Puppet's YAML code violates the YAML standard and doesn't cut out the
    # indentation on lines after the first. In order for Puppet to not indent
    # every line in the file, I've been doing this:
    #
    # foo:
    #   label: |
    #     line 1
    # line 2
    # line 3
    #   next_label: blah
    #
    # This is improper YAML, and the Ruby yaml module can't read it, but the
    # Puppet implementation is just fine with it. We'll have to output it that
    # way too.

    lines = input.split "\n"
    newlines = []
    pipe = false
    pipe_indent = 0
    lines.each do |l|
      line = l
      indent = line[/\A */].size
      if pipe
        if line.start_with? ' '
          pipe = false if indent != pipe_indent
        else
          line = (' '*pipe_indent) + line
        end
      else
        if line =~ /\|\s*$/
          pipe = true
          pipe_indent = indent + 2
        end
      end
      newlines.push line
    end
    return newlines.join "\n"
  end

  def puppet_source_to_path source
    # Given the argument of a "source:" mapping from a Puppet/Hiera YAML file,
    # rearrange it to find the actual source path.
    return source.sub /^puppet:\/\/\/modules\/([^\/]+)/, "#{$PUPPETSRV_BASE}/modules/\\1/files"
  end

  def get_cert_from_hiera target = nil
    # Given a CertTarget, read the certificate whose path is in the
    # Puppet/Hiera host YAML file and return it as an
    # OpenSSL::X509::Certificate object.

    raise ArgumentError.new "Target argument cannot be nil" if target.nil?

    # If usercert is true, things are different. Normally we'd go to
    # "#{$PUPPETSRV_HIERA_HOST_BASE}/#{shorthost}.yaml," find the Puppet/Hiera
    # YAML "hiera::certificate" record whose 'cert'/'path' matches
    # target.certfile.path, and find its source file in
    # $PUPPETSRV_HIERA_CERT_BASE. However, the GOC user cert is not mentioned
    # in a host file. It will instead always be in
    # "#{$PUPPETSRV_HIERA_CERT_BASE}/#{$USERCERT_BASE}_cert.pem". This is no
    # different from using get_cert_from_file.
    if target.certrecord.flag? :usercert
      return get_cert_from_file target.certrecord
    end
    shorthost = (target.host.split '.', 2).first
    yamlpath = "#{$PUPPETSRV_HIERA_HOST_BASE}/#{shorthost}.yaml"
    unless File.exist? yamlpath
      debug_puts 2, "File '#{yamlpath}' does not exist"
      raise FileNotFoundError.new "File '#{yamlpath}' does not exist"
    end
    stdout = File.read yamlpath
    return nil unless stdout.extra_true?
    puppetyaml = YAML.load(fix_yaml_input input = stdout)
    # Now we need to find the specific "hiera::certificate" record in
    # puppetyaml that matches this CertTarget. For this record, its 'cert'/'path'
    allyamlcertrecs = puppetyaml['hiera::certificate']
    unless allyamlcertrecs
      debug_puts 2, "No hiera::certificate mappings found in '#{yamlpath}'"
      raise NoRecordError.new "No records found in '#{yamlpath}'"
    end
    yamlcertrecs = allyamlcertrecs.select { |cn, c| c['cert']['path'] == target.certfile.path }
    if yamlcertrecs.size == 0
      debug_puts 2, "Didn't find a record in '#{yamlpath}' with path '#{target.certfile.path}'"
      raise NoRecordError.new "No record found for a certificate with path #{shorthost}:#{target.certfile.path}"
    end
    if yamlcertrecs.size > 1
      raise RuntimeError.new "Warning: More than one certificate has path #{shorthost}:#{target.certfile.path}"
    end
    certpath = puppet_source_to_path(yamlcertrecs[0][1]['cert']['source'])
    debug_puts 2, "Going to read cert for '#{target.certrecord.cn.to_s}' from '#{certpath}'"
    return OpenSSL::X509::Certificate.new_from_file certpath
  end

  def get_cert_from_file cr = nil
    return OpenSSL::X509::Certificate.new_from_file "#{$PUPPETSRV_CERT_BASE}/#{cr.canonical_certfile}"
  end

  def get_key_from_file cr = nil
    return OpenSSL::PKey::RSA.new_from_file "#{$PUPPETSRV_CERT_BASE}/#{cr.canonical_keyfile}"
  end
end

class Problem
  # Class for a problem, with fields such as human-readable text and a flag to
  # indicate whether it's been fixed.

  attr_accessor :cn, :label, :text, :fixed, :cantfix, :wontfix

  def initialize cn = nil, label = nil, text = '', fixed = false, cantfix = false, wontfix = false
    self.cn = cn
    self.label = label
    self.text = text
    self.fixed = fixed
    self.cantfix = cantfix
    self.wontfix = wontfix
  end

  def done
    # Returns true if what's possible has been done; that is, it's either
    # fixed, or it can't or won't be fixed. Returns false otherwise.
    return true if self.fixed or self.cantfix or self.wontfix
    return false
  end
end

class SANEntry
  # Class for a single SubjectAltName in an X509 certificate. It has a type and
  # a value.

  include Comparable

  attr_accessor :type, :value

  def initialize *args
    # Can initialize with one argument ("<type>:<value>") or two ("<type>",
    # "<value>"). Also works with one argument that is already a SANEntry.
    raise ArgumentError.new 'Maximum 2 arguments' if args.size > 2
    raise ArgumentError.new 'Requires at least 1 argument' if args.size.zero?
    if args.size == 2
      args.each do |a|
        unless a.kind_of? String
          raise ArgumentError.new "Arguments must be Strings (encountered #{a.class.to_s})"
        end
      end
      (self.type, self.value) = args
    elsif args.size == 1
      if args[0].kind_of? SANEntry
        self.type = args[0].type
        self.value = args[0].value
      elsif args[0].kind_of? String
        raise ArgumentError.new "Single string argument must contain a colon (:) ('#{args[0]}' given)" unless args[0].include? ':'
        (self.type, self.value) = args[0].split ':', 2
      else
        raise ArgumentError.new "Argument must be a String or SANEntry (encountered #{args[0].class.to_s})"
      end
    else
      raise ArgumentError.new 'Should not happen! args.size is neither 1 nor 2'
    end
  end

  def to_s
    return "#{self.type}:#{self.value}"
  end

  def inspect
    return '"' + self.to_s + '"'
  end

  def <=> other
    # Compares two SANEntry objects by comparing their two String components
    # with each other. If the given object is not a SANEntry, attempts to
    # convert it to one. This will cause an exception unless it's a String,
    # though.
    other = SANEntry.new other
    type_compare = self.type <=> other.type
    # With two SANEntrys of different types, just compare the types.
    return type_compare unless type_compare == 0
    # If the types are the same, compare using the values.
    return self.value <=> other.value
  end
end

class CertCN
  # Class for the Common Name of a certificate. One wouldn't normally think one
  # would need a class for this, but there are service certificates, which
  # differ from host certificates in that host certificates' CN is just a
  # hostname (e.g. "www.example.com") while service certificates have a service
  # prefix (e.g. "http/www.example.com"). This class implements a 'service'
  # method that returns nil if it isn't a service cert and the service as a
  # string if it is. There is also a to_s method that just returns the CN as a
  # string no matter whether it's a service cert or a host cert (or a user
  # cert), and a 'hostname' method that returns the hostname without the
  # service if it's a service cert and just the hostname otherwise.

  attr_accessor :service, :hostname

  def initialize *args
    # Can initialize with one argument ("<hostname>" or "<service>/<hostname>")
    # or two ("<service>" or '', "<hostname>"). Also works with one argument
    # that is already a CertCN.
    raise ArgumentError.new 'Maximum 2 arguments' if args.size > 2
    raise ArgumentError.new 'Requires at least 1 argument' if args.size.zero?
    if args.size == 2
      args.each do |a|
        unless a.kind_of? String
          raise ArgumentError.new "Arguments must be Strings (encountered #{a.class.to_s})"
        end
      end
      @service, @hostname = args
    elsif args.size == 1
      if args[0].kind_of? CertCN
        @service = args[0].service
        @hostname = args[0].hostname
      elsif args[0].kind_of? String
        @service = nil
        if args[0].index '/'
          @service, @hostname = args[0].split '/', 2
        else
          @hostname = args[0]
        end
      else
        raise ArgumentError.new "Argument must be a String or CertCN (encountered #{args[0].class.to_s})"
      end
    else
      raise ArgumentError.new 'Should not happen! args.size is neither 1 nor 2'
    end
  end

  def service?
    return @service.extra_true?
  end

  def to_s
    if @service.extra_true?
      return "#{@service}/#{@hostname}"
    else
      return @hostname
    end
  end

  def inspect
    return '"' + self.to_s + '"'
  end

  def <=> other
    # Compares two CertCN objects by comparing their two String components with
    # each other. If the given object is not a CertCN, attempts to convert it
    # to one. This will cause an exception unless it's a String, though.
    other = CertCN.new other = other
    # Deal with the situation where service is nil (a host or user cert).
    if self.service == other.service
      service_compare = 0
    elsif self.service.nil? # and other.service is not nil
      service_compare = -1
    elsif other.service.nil? # and self.service is not nil
      service_compare = 1
    else # neither is nil, and they're not equal
      service_compare = self.service <=> other.service
    end
    # With two CertCNs of different services, just compare the services.
    return service_compare unless service_compare == 0
    # If the services are the same, compare using the hostnames.
    return self.hostname <=> other.hostname
  end
end

class CertKeyPair
  # A class consisting of an X509 certificate and its RSA secret key. These are
  # in the form of an OpenSSL::X509::Certificate and an
  # OpenSSL::PKey::RSA. Because sometimes there are operations that require
  # both.

  attr_accessor :cert, :key

  private

  include CertUtils

  public

  def initialize cert = nil, key = nil
    raise ArgumentError.new "Certificate must be OpenSSL::X509::Certificate (instead of #{cert.class.to_s})" unless cert.kind_of? OpenSSL::X509::Certificate
    raise ArgumentError.new "Key must be OpenSSL::PKey::RSA (instead of #{key.class.to_s})" unless key.kind_of? OpenSSL::PKey::RSA
    @cert = cert
    @key = key
  end

  def consistency_check
    # Determine whether cert and key match cryptographically.
    nonce = generate_nonce size = 16
    pubkey = @cert.public_key
    encrypt = pubkey.public_encrypt nonce
    begin
      decrypt = @key.private_decrypt encrypt
    rescue OpenSSL::PKey::RSAError => e
      if e.message == 'padding check failed'
        return false
      end
#      debug_puts 1, YAML.dump @key.to_pem
      raise e
    end
    return decrypt == nonce
  end

  def <=> other = nil
    # When sorting, sort by subject.
    return self.cert.subject <=> other.cert.subject
  end
end

class FileRecord
  # A FileRecord stores the path, user and group ownerships, and permission
  # mode for one file. A CertTarget will have two of these: one for the
  # certificate and one for the key.

  attr_reader :path, :user, :group, :mode

  def initialize path = nil, user = nil, group = nil, mode = nil
    self.path = path
    self.user = user
    self.group = group
    self.mode = mode
  end

  def path= path
    raise ArgumentError.new "Path must be a String" unless path.kind_of? String
    @path = path
  end

  def user= user
    raise ArgumentError.new "User must be a String" unless user.kind_of? String
    @user = user
  end

  def group= group
    raise ArgumentError.new "Group must be a String" unless group.kind_of? String
    @group = group
  end

  def mode= mode
    raise ArgumentError.new "Mode must be a String or Integer" unless mode.kind_of? String or mode.kind_of? Integer
    mode = mode.to_i(8) if mode.kind_of? String
    @mode = mode
  end
end

class CertTarget
  # A "target" for a certificate describes where on a target host a certificate
  # (and its key) are expected to exist, including not just the host and path
  # but also ownerships and permission modes. Puppet/Hiera will do the
  # installing, not this script; we just have to put the right YAML data into
  # the right Puppet/Hiera files for it. Targets can have flags as well. Note
  # that the :host attribute is not necessarily the same as the host in the
  # certificate's CN.

  attr_reader :host, :certfile, :keyfile, :notify, :flags, :certrecord

  private

  include CertUtils

  def compare_with_hiera target
    # Compare this target's data with that in the Puppet/Hiera file for the
    # host defined in the target.

    problems = []
    shorthost = (host.split '.', 2).first
    yamlpath = "#{$PUPPETSRV_HIERA_HOST_BASE}/#{shorthost}.yaml"
    # It's completely possible the file doesn't exist, such as in the case of a
    # new certificate.
    unless File.exist? yamlpath
      problems.push Problem.new cn = target.certrecord.cn, label = :hiera_not_found,
      text = "Hiera file '#{yamlpath}' not found."
      return problems
    end
    yaml = YAML.load(fix_yaml_input input = (File.read yamlpath))
    unless yaml.kind_of? Hash
      problems.push Problem.new cn = target.certrecord.cn, label = :yaml_not_found,
      text = "Unable to read YAML file '#{yamlpath}'."
      return problems
    end
    unless yaml.key? 'hiera::certificate'
      problems.push Problem.new cn = target.certrecord.cn, label = :yaml_not_found,
      text = "No hiera::certificate records found in YAML file '#{yamlpath}'."
      return problems
    end
    # Find mappings with the expected destination path.
    t_yaml = yaml['hiera::certificate'].select do |cn, y|
      y['cert']['path'] == target.certfile.path
    end
    unless t_yaml.size > 0
      problems.push Problem.new cn = target.certrecord.cn, label = :yaml_not_found,
      text = "No matching hiera::certificate record found in YAML file '#{yamlpath}'."
      return problems
    end
    if t_yaml.size > 1
      problems.push Problem.new cn = target.certrecord.cn, label = :duplicate_yaml,
      text = "More than one matching hiera::certificate record in YAML file '#{yamlpath}'."
      return problems
    end
    # We've found exactly one result. This must be the YAML mapping
    # corresponding to the target we're trying to check.
    t_yaml = t_yaml[0][1]
    t_cert_yaml = t_yaml['cert']
    t_key_yaml = t_yaml['key']
    # Make sure the cert source file exists.
    t_cert_path = puppet_source_to_path(t_cert_yaml['source'])
    unless File.exists? t_cert_path
      problems.push Problem.new cn = target.certrecord.cn, label = :cert_source_not_found,
      text = "Cert source path '#{t_cert_path}' not found."
    end
    # Check out ownerships/permissions for cert.
    if t_cert_yaml['owner'] != target.certfile.user
      problems.push Problem.new cn = target.certrecord.cn, label = :cert_owner_mismatch,
      text = "Owner mismatch in cert ('#{t_cert_yaml['owner']}' vs. '#{target.certfile.user}')."
    end
    if t_cert_yaml['group'] != target.certfile.group
      problems.push Problem.new cn = target.certrecord.cn, label = :cert_group_mismatch,
      text = "Group mismatch in cert ('#{t_cert_yaml['group']}' vs. '#{target.certfile.group}')."
    end
    if t_cert_yaml['mode'] != target.certfile.mode
      problems.push Problem.new cn = target.certrecord.cn, label = :cert_mode_mismatch,
      text = "Mode mismatch in cert ('#{t_cert_yaml['mode'].to_s(8)}' vs. '#{target.certfile.mode.to_s(8)}')."
    end
    # Check out ownerships/permissions for key.
    if t_key_yaml['owner'] != target.keyfile.user
      problems.push Problem.new cn = target.certrecord.cn, label = :key_owner_mismatch,
      text = "Owner mismatch in key ('#{t_key_yaml['owner']}' vs. '#{target.keyfile.user}')."
    end
    if t_key_yaml['group'] != target.keyfile.group
      problems.push Problem.new cn = target.certrecord.cn, label = :key_group_mismatch,
      text = "Group mismatch in key ('#{t_key_yaml['group']}' vs. '#{target.keyfile.group}')."
    end
    if t_key_yaml['mode'] != target.keyfile.mode
      problems.push Problem.new cn = target.certrecord.cn, label = :key_mode_mismatch,
      text = "Mode mismatch in key ('#{t_key_yaml['mode'].to_s(8)}' vs. '#{target.keyfile.mode.to_s(8)}')."
    end
    return problems
  end # def compare_with_hiera

  def compare_with_eyaml target
  end

  public

  def initialize host = nil, certfile = nil, keyfile = nil, notify = nil,
                 flags = Set.new
    self.host = host
    self.certfile = certfile
    self.keyfile = keyfile
    self.notify = notify
    self.flags = flags
  end

  def host= host
    raise ArgumentError.new "Host must be a String" unless host.kind_of? String
    @host = host
  end

  def certfile= certfile
    raise ArgumentError.new "Certfile argument must be a FileRecord" unless certfile.kind_of? FileRecord
    @certfile = certfile
  end

  def keyfile= keyfile
    raise ArgumentError.new "Keyfile argument must be a FileRecord" unless keyfile.kind_of? FileRecord
    @keyfile = keyfile
  end

  def notify= notify
    raise ArgumentError.new "Notify must be nil or an Array" unless notify.nil? or notify.kind_of? Array
    @notify = notify
  end

  def flags= flags = Set.new
    raise ArgumentError.new "Flags must be a Set" unless flags.kind_of? Set
    @flags = flags
  end

  def flag_set flag
    @flags.add flag
  end

  def flag_clear flag
    @flags.reject! { |i| i == flag }
  end

  def flag? flag
    return @flags.include? flag
  end

  def certrecord= certrec
    raise ArgumentError.new "Argument must be a CertRecord (not a #{certrec.class.to_s})" unless certrec.kind_of? CertRecord
    @certrecord = certrec
  end

  def self.new_from_yaml(yaml = nil, cn = nil)
    # Initialize a CertTarget from YAML data. Raises exceptions if the data
    # isn't structured properly.
    host = yaml['host']

    # Certificate: Begin with defaults
    default_path_base = '/etc/grid-security'
    if cn.service?
      default_path_base += "/#{cn.service}"
    else
      default_path_base += "/host"
    end
    certfile = FileRecord.new path = "#{default_path_base}/cert.pem",
                              user = 'root',
                              group = 'root',
                              mode = 0644
    if yaml.key? 'cert'
      raise ConfigError.new "Cert not Hash in #{host}" unless yaml['cert'].kind_of? Hash
      if yaml['cert'].key? 'path'
        if yaml['cert']['path'].start_with? '/'
          # Absolute path
          certfile.path = yaml['cert']['path']
        else
          # Relative path: put in default directory
          certfile.path = "#{default_path_base}/#{yaml['cert']['path']}"
        end
      end
      if yaml['cert'].key? 'user'
        certfile.user = yaml['cert']['user']
      end
      if yaml['cert'].key? 'group'
        certfile.group = yaml['cert']['group']
      end
      if yaml['cert'].key? 'mode'
        if yaml['cert']['mode'].kind_of? Integer
          certfile.mode = yaml['cert']['mode']
        elsif yaml['cert']['mode'].kind_of? String
          certfile.mode = yaml['cert']['mode'].to_i(8)
        else
          raise ConfigError.new "targets/#{host}/cert/mode has unexpected class"
        end
      end
    end

    # Key: Begin with defaults
    keyfile = FileRecord.new path = "#{default_path_base}/key.pem",
                             user = certfile.user,
                             group = certfile.group,
                             mode = (certfile.mode & 0700)
    if yaml.key? 'key'
      raise ConfigError.new "Key not Hash in #{host}" unless yaml['key'].kind_of? Hash
      if yaml['key'].key? 'path'
        if yaml['key']['path'].start_with? '/'
          # Absolute path
          keyfile.path = yaml['key']['path']
        else
          # Relative path: put in same directory as cert
          keyfile.path = (File.dirname certfile.path) + '/' + yaml['key']['path']
        end
      end
      if yaml['key'].key? 'user'
        keyfile.user = yaml['key']['user']
      end
      if yaml['key'].key? 'group'
        keyfile.group = yaml['key']['group']
      end
      if yaml['key'].key? 'mode'
        if yaml['key']['mode'].kind_of? Integer
          keyfile.mode = yaml['key']['mode']
        elsif yaml['key']['mode'].kind_of? String
          keyfile.mode = yaml['key']['mode'].to_i(8)
        else
          raise ConfigError.new "targets/#{host}/key/mode has unexpected class"
        end
      end
    end

    # Notify: Just an array of strings usually
    notify = nil
    if yaml.key? 'notify'
      raise ConfigError.new "targets/#{host}/notify not a sequence" unless yaml['notify'].kind_of? Array
      notify = yaml['notify']
    end

    # Flags: Starts out empty
    flags = Set.new
    if yaml.key? 'flags'
      raise ConfigError.new "targets/#{host}/flags not a sequence" unless yaml['flags'].kind_of? Array
      flags = yaml['flags'].to_set
    end

    # Create our new CertTarget
    self.new host = host, certfile = certfile, keyfile = keyfile, notify = notify,
             flags = flags
  end

  def look_for_trouble
    # With $opt[:yaml] (the -2 comand-line option), looks for discrepancie
    # between the target data in memory and what's in the Puppet/Hiera file,
    # setting the :needs_yaml flag if there is a difference. With $opt[:eyaml]
    # (the -3 command-line option), also looks for discrepancies between the
    # key in memory and what's in the encrypted data within the Hiera file,
    # setting the :needs_eyaml flag if there's a difference. Either way,
    # creates Problem objects and returns them if there are problems.
    return_problems = []
    if $opt[:yaml]
      # We have target data -- host, cert file, key file, notify array. Get the
      # data for this target from the Puppet/Hiera host YAML file and compare
      # them, noting discrepancies.
      problems = compare_with_hiera self
      self.flag_set :needs_yaml if problems.size > 0
      return_problems += problems
    end
    if $opt[:eyaml]
      # We have the ability to decrypt the key data from the Hiera host YAML
      # file, so do so, and compare the key data with the key in memory. Note
      # any discrepancies.
      problems = compare_with_eyaml self
      self.flag_set :needs_eyaml if problems.size > 0
      return_problems += problems
    end
    return return_problems
  end

#  def certobj force = false
#    # Obtains the OpenSSL::X509::Certificate object representing the
#    # certificate the Puppet server associates with this target. Returns nil if
#    # it can't obtain it (one isn't defined or something), or raises an
#    # exception if it tries and fails.

#    return @certobj if @certobj

#    # Check whether the Puppet server is up.
#    return nil unless remote_up host = $PUPPETSRV_HOST

#    if $opt[:yaml]
#      begin
#        @certobj = x509_get_remote_hiera host = @host, path = @certfile.path
#      rescue FileNotFoundError
#        debug_puts "Not found: #{@host}:#{@certfile.path}"
#        return nil
#      end
#    else
#      @certobj = get_cert_file(cn = @certrecord.cn,
#                               usercert = @certrecord.flag?(:usercert))
##      shorthost = (@host.split '.').first
##      @certobj = x509_get_remote host = $PUPPETSRV_HOST, path = "#{$PUPPETSRV_CERT_BASE}/#{shorthost}.*_cert.pem"
#      debug_puts "Retrieved #{@certobj.subject}"
#      abort if @certobj.nil?
#    end
#    # Return what we've got.
#    return @certobj
#  end

#  def keyobj
#    # See certobj, only for keys.
#    return @keyobj if @keyobj
#    return nil if remote_up host = $PUPPETSRV_HOST

#    if $opt[:eyaml]
#      begin
##        @keyobj = rsa_get_remote_eyaml host = @host, path = @keyfile.path
#      rescue FileNotFoundError
#        debug_puts "Not found: #{@host}:#{@keyfile.path}"
#        return nil
#      end
#    else
#      shorthost = (@host.split '.').first
#      @keyobj = rsa_get_remote host = $PUPPETSRV_HOST, path = "#{$PUPPETSRV_CERT_BASE}/#{shorthost}.*_key.pem"
#      debug_puts "Retrieved #{@keyobj.to_pem}"
#    end
#    return @keyobj
#  end

  # def copy_cert_to_puppet cert = self.certobj, key = self.keyobj
  #   # Calls write_puppet_cert to write the certificate to the Puppet server and
  #   # do whatever needs to be done related to that.

  #   # If a cert argument is given, uses that as the cert data to write to the
  #   # file. Otherwise, uses the cert in self.certobj.
  #   write_puppet_cert pair = (CertKeyPair.new cert = cert, key = key),
  #                     certfile = self.certfile,
  #                     keyfile = self.keyfile,
  #                     notify = self.notify
  # end

  # def copy_key_to_puppet cert = self.certobj, key = self.keyobj
  #   # See copy_cert_to_puppet.

  #   write_puppet_key pair = (CertKeyPair.new cert = cert, key = key),
  #                    certfile = self.certfile,
  #                    keyfile = self.keyfile,
  #                    notify = self.notify
  # end
end

class CertRecord
  # A class to represent a certificate record as defined in the configuration
  # file. The actual certificate and key are not represented here! This is
  # because the certificate record has overall data about what a certificate is
  # supposed to look like, not what it actually does look like or what it
  # should look like in any of its various locations.
  #
  # Attributes include:
  # cn: the Common Name
  # desc: a text description
  # type: keyword: 'cilogon', 'incommon', 'internal', etc.
  # flags: set of text flags
  # msg: message to print to user after renewing
  # renewed: whether the cert has been renewed or not (true/false)
  # san: SANEntrys object representing cert's SAN field, if any
  # last_checked: timestamp: when last checked?
  # last_status: label indicating whether 'OK' or not when last checked
  # last_ok: timestamp: last 'OK' status

  attr_reader :cn, :type, :targets, :flags,\
              :last_checked, :last_status, :last_ok

  attr_writer :cert, :key

  attr_accessor :desc, :msg, :san, :renewed, :requestvo

  private

  include CertUtils

  def get_cert_and_key force = false
    # Attempts to ensure that @cert and @key contain a valid certificate and
    # key, reading them from files in $PUPPETSRV_CERT_BASE if necessary. This
    # method returns true either if @cert and @key are already set or if it set
    # them to a valid cert and key. It returns false if they weren't already
    # set and it couldn't find them or it found them and they weren't valid,
    # assuming it didn't raise an exception by that time. Setting the force
    # argument to true causes this method to always read the cert and key from
    # files, even if @cert and @key are already set.

    # A "valid" certificate and key, above, means that the certificate must
    # exist and not be expired, and the key must exist and cryptographically
    # match the certificate. That last criterion is why this isn't two separate
    # methods. A cert is of no use without a key.

    # If we already got them, don't get them again.
    return true if !force and @cert and @key

    # Attempt to read the cert. If the :yaml option is set (the -2 command-line
    # option), go to the Puppet/Hiera YAML files for the host in question and
    # find the path to the certificate from there. Otherwise, assume the file
    # is at a standard location and read it from there.
    if !self.flag? :usercert and $opt[:yaml]
      cert = nil
      # Use the first target that works.
      self.targets.each do |target|
        begin
          debug_puts 2, "Attempting to read cert from Hiera files for target '#{target.host}:#{target.certfile.path}', a target of '#{target.certrecord.cn.to_s}'"
          cert = get_cert_from_hiera target
          debug_puts 2, "get_cert_from_hiera returned without exception"
        rescue NoRecordError
          debug_puts 2, "Got NoRecordError exception"
          target.flag_set :needs_yaml
          break
        rescue FileNotFoundError
          next
        rescue
          raise
        else
          break unless cert.nil?
          debug_puts 2, "(but got a nil cert)"
        end
      end
      if cert.nil?
        debug_puts 2, "Unable to find cert from any targets for '#{self.desc}'"
        self.flag_set :needs_yaml
      end
    else
      # If the -2 option is not set, just go to the canonical location.
      begin
        cert = get_cert_from_file self
      rescue FileNotFoundError
        cert = nil
      end
    end
    # Were we able to read the file? Is the cert still valid?
    if cert.nil?
      self.flag_set :cert_unreadable
      return false
    elsif cert.expiring? threshold = $EXPIRE_THRESHOLD.to_f
      self.flag_set :cert_expiring
    end

    # Now try to get the key. If the :eyaml option is set (the -3 command-line
    # option), try to decrypt it from the eYAML files on the Puppet server, but
    # if not, go to the cert files directory on the Puppet server, where we are
    # putting them until we know the eYAML stuff works for sure.
    if $opt[:eyaml]
      # To be implemented
    else
      key = get_key_from_file self
    end

    # Found both a cert and a key.
    unless cert.nil? or key.nil?
      # Found cert and key -- do they match?
      if (CertKeyPair.new cert = cert, key = key).consistency_check
        @cert = cert
        @key = key
        return true
      else
        # Set @key to nil so this method won't initially think the cert and key
        # are valid if it's called again, and so the rest of the script won't
        # think they're valid (though the false return value also says that,
        # this will be a lasting sign).
        debug_puts 1, "Cert/key crypto mismatch for '#{self.cn.to_s}'"
        key = nil
        return false
      end
    end

    # At this point either cert or key is nil. If there's a cert but no key,
    # this is OK if we're not using eYAML for keys. This means we're doing
    # eYAML by hand, meaning the keys are out of reach of this script.
    if cert and !$opt.key? :eyaml
      debug_puts 2, "No key, but not set to read from eYAML"
      @cert = cert
      return false
    end

    debug_puts 1, "Couldn't find a valid cert and matching key for #{self.desc}"
    return false
  end

  public

  def initialize args
    default = {
      :cn => nil,
      :desc => nil,
      :type => nil,
      :targets => nil,
      :flags => Set.new,
      :msg => nil,
      :san => nil,
      :renewed => nil,
      :requestvo => nil,
      :cert => nil,
      :key => nil,
      :last_checked => 0,
      :last_status => '',
      :last_ok => 0,
    }
    default.each do |attr, df|
      if args.key? attr
        value = args[attr]
      else
        value = df
      end
      (self.method((attr.to_s + '=').to_sym)).call value
    end
  end

  def self.new_from_yaml yaml = nil
    # Create a new CertRecord from YAML data.

    # We can't really have a cert unless we know what kind it is and what it's
    # for.
    unless yaml['desc'].extra_true?
      raise ConfigError.new "Certificate without description in #{$CONFIG}"
    end
    unless yaml['type'].extra_true?
      raise ConfigError.new "No type given for '#{yaml['desc']}'"
    end
    unless yaml['cn'].extra_true?
      raise ConfigError.new "No CN given for '#{yaml['desc']}'"
    end

    # Start handling the attributes.
    cn = CertCN.new yaml['cn']
    yaml['msg'] ||= ''
    if yaml.key? 'flags'
      unless yaml['flags'].kind_of? Hash
        raise ConfigError.new "'#{yaml['desc']}' has 'flags' element that is not a mapping"
      end
      yaml['flags'] = yaml['flags'].keys.map { |f| f.to_sym }.to_set
    else
      yaml['flags'] = Set.new
    end
    if yaml.key? 'targets'
      unless yaml['targets'].kind_of? Array
        raise ConfigError.new "'#{yaml['desc']} has 'targets' element that is not a sequence"
      end
      yaml['targets'] = yaml['targets'].map { |a| CertTarget.new_from_yaml(a, cn) }
    end
    if yaml.key? 'san'
      unless yaml['san'].kind_of? Array
        raise ConfigError.new "'#{yaml['desc']} has 'san' element that is not a sequence"
      end
      if yaml['san'].select { |s| !s.include? ':' }.size > 0
        raise ConfigError.new "SAN array for '#{yaml['desc']} has names that are not given a type; alternative names should have format type:data, where type is DNS, IP, email, etc."
      end
    end
    newcr = self.new({
                       :cn => cn,
                       :desc => yaml['desc'],
                       :type => yaml['type'],
                       :targets => yaml['targets'],
                       :flags => yaml['flags'],
                       :msg => yaml['msg'],
                       :san => yaml['san'],
                       :requestvo => yaml['requestvo'],
                     })
#    nputs YAML.dump newcr
    if newcr.targets and newcr.targets.size > 0
      newcr.targets.each do |t|
        t.certrecord = newcr
      end
    end
    return newcr
  end

  def cn= cn
    @cn = CertCN.new cn
  end

  def desc= desc
    raise ArgumentError.new "desc must be nil or a String (not #{desc.class})" unless desc.kind_of? String or desc.nil?
    @desc = desc
  end

  def type= type
    raise ArgumentError.new 'type must be nil or a String' unless type.kind_of? String or type.nil?
    @type = type
  end

  def targets= targets = nil
    raise ArgumentError.new 'targets must be nil or an Array' unless targets.nil? or targets.kind_of? Array
    @targets = targets
  end

  def msg= msg
    msg ||= ''
    raise ArgumentError.new 'msg must be a String' unless msg.kind_of? String
    @msg = msg
  end

  def san= san
    # Ensures that the san attribute will be an array of SANEntry objects.
    return unless san.extra_true?
    @san = []
    san.each do |s|
      @san.push(SANEntry.new s)
    end
  end

  def flags= flags = Set.new
    raise ArgumentError.new "flags must be a Set (not a #{flags.class})" unless flags.kind_of? Set
    @flags = flags
  end

  def flag_set flag
    @flags.add flag
  end

  def flag_clear flag
    @flags.reject! { |i| i == flag }
  end

  def flag? flag
    return @flags.include? flag
  end

  def last_checked= last_checked
    last_checked ||= 0
    raise ArgumentError.new 'last_checked must be an Integer' unless last_checked.kind_of? Integer
    @last_checked = last_checked
  end

  def last_status= last_status
    last_status ||= ''
    raise ArgumentError.new 'last_status must be a String' unless last_status.kind_of? String
    @last_status = last_status
  end

  def last_ok= last_ok
    last_ok ||= 0
    raise ArgumentError.new 'last_ok must be an Integer' unless last_ok.kind_of? Integer
    @last_ok = last_ok
  end

  def skipping?
    # Given a hash of the command-line options, looks at the options
    # (specifically the -c and -s ones) to see whether we're skipping that
    # record. Returns true if skipping, false if not.

    # This means that the user specified '-c <cn>' to test only one particular CN.
    return true if $opt.key? :cn and self.cn.to_s != $opt[:cn]

    # This means that the user specified '-s <cn>' to skip one particular CN.
    return true if $opt.key? :skip and self.cn.to_s == $opt[:skip]
    return false
  end

  def too_recent?
    # Checks to see whether the given certificate record's last_ok value is
    # more recent than $RECHECK_THRESHOLD. Returns true if the last_ok is too
    # recent. Returns false if it isn't, or if the '-f' option was given.
    if $opt[:force]
      debug_puts 1, "Forcing check with -f"
      return false
    end
    if $opt[:debug]           # Print something useful in debug mode.
      if ($now - self.last_ok) < $RECHECK_THRESHOLD
        debug_puts 1, "  #{self.desc} checked out OK recently"
      else
        last_status = '(undef)'
        unless self.last_status.empty?
          last_status = self.last_status
        end
        last_checked = '(undef)'
        unless self.last_checked == 0
          last_checked = (($now - self.last_checked)/86400).to_s
        end
        debug_puts 1, "  #{self.desc} last_status was: #{last_status}, #{last_checked} days ago"
      end
    end
    return ($now - self.last_ok) < $RECHECK_THRESHOLD
  end

  def nondefault_san
    # See the method of the same name in CertLocation, but this one is for
    # CertRecord objects. In other words, this works with the record from the
    # config file that states what records should exist in the SAN field, not
    # what actually exists in a real certificate. Unlike the san method, which
    # just returns whatever SAN entries are listed in the config file, this
    # method makes sure that the CN doesn't appear and that, in the case of
    # host/service certificates, there are no email records.
    return nil if self.san.nil?
    sans = self.san.clone
    if self.flag? :usercert
      ignore_san = SANEntry.new 'email', self.cn.hostname
    else
      sans.reject! { |san| san.type == 'email' }
      ignore_san = SANEntry.new 'DNS', self.cn.hostname
    end
    if ignore_san
      sans.reject! { |san| san == ignore_san }
    end
    return sans
  end

  def cert force = false
    # Returns an unexpired cert that has a matching key from among the record's
    # targets, falling back to the cert server if necessary. Will respond from
    # cached result unless the force argument is true.
    get_cert_and_key force = force
    debug_puts 2, "cert method for '#{self.desc}' called get_cert_and_key and got a nil result" if @cert.nil?
    return @cert if @cert
    return nil
  end

  def key force = false
    # Similar to the cert method above, only for the key.
    get_cert_and_key force = force
    debug_puts 2, "cert method for '#{self.desc}' called get_cert_and_key and got a nil result" if @cert.nil?
    return @key if @key
    return nil
  end

  def canonical_prefix
    # Returns the prefix for the standardized certificate and key filenames,
    # which is:
    #
    # host certs: <fqdn>
    #
    # service certs: <fqdn>
    #
    # user certs: <email>, where <email> is the user email with @ changed to _

    if self.flag? :usercert
      # There could be multiple emails in the SAN, but that's never
      # happened. We'll cross that bridge if we ever come to it.
      prefix = self.san.select { |s| s.type == 'email' }.first.value
      prefix.gsub! %r'[^\w.]', '_'
    else
      prefix = self.cn.hostname
    end
    return prefix
  end

  def canonical_prefix_plus_type
    # Returns the prefix and type for the standardized certificate and key
    # filenames, which is:
    #
    # host certs: <fqdn>
    #
    # service certs: <fqdn>_<svc>
    #
    # user certs: <email>_user, where <email is the user email with @ changed
    # to _

    pfx = self.canonical_prefix
    if self.flag? :usercert
      pfx += "_user"
    elsif self.cn.service?
      pfx += "_#{self.cn.service}"
    end
    return pfx
  end

  def canonical_certfile
    # Returns the standardized certificate filename, which is:
    #
    # host certs: <fqdn>_cert.pem
    #
    # service certs: <fqdn>_<svc>_cert.pem
    #
    # user certs: <email>_user_cert.pem where <email> is the user email with @
    # changed to _

    return "#{self.canonical_prefix_plus_type}_cert.pem"
  end

  def canonical_keyfile
    # Like canonical_certfile, only for the key file.

    return "#{self.canonical_prefix_plus_type}_key.pem"
  end

  def canonical_prefix_plus_fq
    # Returns the "fully qualified" certificate filename prefix, which is:
    #
    # host certs: <fqdn>_<type>_<expdate>
    #
    # service certs: <fqdn>_<svc>_<type>_<expdate>
    #
    # user certs: <email>_user_<type>_<expdate>
    #
    # where
    # <type> is the cert type/issuer keyword, 'incommon', 'cilogon', etc.
    # <expdate> is the expiration date, YYYY-MM-DD
    # <email> is the user email with @ changed to _

    expdate = self.cert.not_after.strftime '%F'
    return "#{self.canonical_prefix_plus_type}_#{self.type}_#{expdate}"
  end

  def canonical_certfile_fq
    return "#{self.canonical_prefix_plus_fq}_cert.pem"
  end

  def canonical_keyfile_fq
    return "#{self.canonical_prefix_plus_fq}_key.pem"
  end

  def cert_fp force = false
    # Returns the certificate fingerprint. This will cause the cert to be read
    # and cached if it hasn't already been. If the read failed the first time,
    # this will cause another read attempt.
    cert = self.cert force = force
    return nil if cert.nil?
    return (($digester.digest cert.to_der).unpack 'H*')[0]
  end

  def cert_subject force = false
    # Returns the certificate subject as an OpenSSL::X509::Name object. This
    # can be made into a string via to_s or an array of components using to_a.
    cert = self.cert force = force
    return nil if cert.nil?
    return cert.subject
  end

  def cert_cn force = false
    # Returns the Common Name of the subject of the certificate. Note that this
    # is not necessarily the same as the 'cn' method, which returns the CN that
    # the configuration file thinks the cert should have. This method returns
    # the CN that the cert read from the file really has.
    cert = self.cert force = force
    return nil if cert.nil?
    cn = cert.cn
    return nil if cn.nil?
    return CertCN.new cn
  end

  def cert_not_before force = false
    cert = self.cert force = force
    return nil if cert.nil?
    return cert.not_before.to_i
  end

  def cert_not_after force = false
    cert = self.cert force = force
    return nil if cert.nil?
    return cert.not_after.to_i
  end

  def cert_daysleft force = false
    # Returns the number of days left before the certificate expires. This
    # number will be negative if it has already expired! It will return nil if
    # the cert can't be read. But in that case there will probably already have
    # been an exception.

    cert = self.cert force = force
    return nil if cert.nil?
    return ((self.cert_not_after force = force).to_f - $now.to_f)/86400.0
  end

  def cert_expired? force = false
    # Returns true if the cert has expired.
    return true if (self.cert_daysleft force = force) <= 0.0
    return false
  end

  def cert_expiring? force = false
    # Returns true if the cert either has expired or is within
    # $EXPIRE_THRESHOLD days of expiring.
    return true if (self.cert_daysleft force = force) <= $EXPIRE_THRESHOLD.to_f
    return false
  end

  def cert_san force = false
    # Returns an array of SANEntry objects of the subjectAltName extension's
    # contents, if it exists. Note that this is different from the 'san'
    # method, which returns the SANs that should exist. This method returns the
    # SANs that actually exist in the cert file.
    cert = self.cert force = force
    return nil if cert.nil?
    sanexts = cert.extensions.select { |e| e.oid == 'subjectAltName' }
    sans = []
    # It probably isn't possible for there to be more than one SAN
    # extension. But if it happens, we're ready for it.
    sanexts.each do |sanext|
      # The method returns them in comma-separated form.
      tempsans = (sanext.value.split %r'\s*,\s*').map { |s| SANEntry.new s }
      sans += tempsans
    end
    return sans
  end

  def look_for_trouble
    # Check the cert record for problems and fix any problems we can. Returns
    # the number of problems found and the number of problems
    # fixed. Requesting/renewing certs should be queued, but other problems can
    # be fixed right now.

    problems = []
    if $opt.key? :debug
      debug_puts 1, "Now checking '#{self.desc}' ..."
    else
      progress_puts "Now checking '#{self.desc}' ..."
    end

    # We're going to compare the SAN of the file on the server with what we
    # expect it to be. This is a bit complicated because, according to the
    # standard, a multi-domain service or host cert must contain the CN itself
    # in its SAN field. Put another way, if it isn't a user cert and if it has
    # a SAN field, the CN must be in that SAN field. However, this script aims
    # for convenience in the config file, so there's no need to enter it
    # there. So what we're going to do is (if it's got a SAN field at all and
    # isn't a host cert) create an expected SAN array for the cert record and
    # see if the cert on the server has a SAN field with the same entries.
    expected_sans = nil
    unless self.flag? :usercert
      if self.san.extra_true?
        # Make a real copy of the SAN list so we can modify it without
        # affecting the original. Can't just do "esans = self.san".
        esans = Marshal.load(Marshal.dump self.san)
        esans.push(SANEntry.new 'DNS', self.cn.hostname)
        esans.sort!     # Sorted for later comparison
        # No duplicates
        seen = Set.new
        expected_sans = Array.new
        esans.each do |san|
          san_str = san.to_s
          unless seen.include? san_str
            expected_sans.push san
            seen.add san_str
          end
        end
      end
    end

    problems = []
    unless self.cert
      problems.push Problem.new cn = self.cn, label = :cert_unreadable,
      text = "Certificate unreadable."
    end
    # The key's not being found might not actually be a problem. If we're using
    # eYAML, the key will be encrypted in the Hiera YAML file, not in a
    # separate file on the server. But even if it's not there or we're not
    # using eYAML, the sysadmin may have squirreled the key away somewhere more
    # secure than leaving it out in plaintext on the Puppet server. If it's not
    # there, don't panic, just don't check it. It's not as if the key has any
    # expiration information anyway.
#    unless self.key
#      problems.push Problem.new cn = self.cn, label = :key_unreadable,
#      text = "Key unreadable."
#    end
    # Now, if both cert and key exist, we can perform further tests.
    if self.cert
      # Does the subject match what we expect?
      unless self.cert_cn.to_s == self.cn.to_s
        self.flag_set :cn_mismatch
        problems.push Problem.new cn = self.cn, label = :subject_mismatch,
        text = "Subject mismatch ('#{self.cert_cn.to_s}' vs. '#{self.cn.to_s}')."
      end
      # Does the SAN field match what we expect (if we expect one)?
      if expected_sans.extra_true?
        if self.cert_san.nil?
          problems.push Problem.new cn = self.cn, label = :san_mismatch,
          text = "SAN mismatch (nil vs. #{expected_sans.map { |s| s.to_s }.join ', '})"
        else
          certsans = self.cert_san.select { |s| s.type != 'email' }.sort
          unless certsans == expected_sans
            self.flag_set :san_mismatch
            problems.push Problem.new cn = self.cn, label = :san_mismatch,
            text = "SAN mismatch (#{certsans.map { |s| s.to_s }.join ', '} vs. #{expected_sans.map { |s| s.to_s }.join ', '})"
          end
        end
      end
      if self.flag? :cert_expiring or $opt[:srvexpire]
        # Is the certificate expired or expiring?
        problems.push Problem.new cn = self.cn, label = :cert_expiring,
        text = "Cert expiring in #{format '%.2f', self.cert_daysleft} days."
      end
      if self.key
        # Do the cert and key cryptographically match?
        unless (CertKeyPair.new cert = self.cert, key = self.key).consistency_check
          self.flag_set :crypto_mismatch
          problems.push Problem.new cn = self.cn, label = :crypto_mismatch,
          text = "Cert and key not cryptographically compatible."
        end
      end
    end

    unless self.flag? :usercert
      # If the -2 option was given on the command line, check out the
      # Puppet/Hiera YAML file for each target. Set :needs_yaml on both this cert
      # record and on the target record if there's a difference between what's in
      # the file and what we expect. Likewise with the -3 option, only that means
      # a difference between the encrypted key in the YAML file and the one we
      # have in memory.
      if $opt[:yaml]
        if self.targets
          self.targets.each do |t|
            problems += t.look_for_trouble
            if t.flag? :needs_yaml
              self.flag_set :needs_yaml
            end
            if t.flag? :needs_eyaml
              self.flag_set :needs_eyaml
            end
          end
        else
          raise ConfigError.new "Cert '#{self.cn.to_s}' has no targets"
        end
      end
    end

    # Now that we've collected all the problems, let's see if there are any
    # we can solve.
    if (problems.count { |p| !p.done }) > 0
      nputs "\n*** Oddities about '#{self.desc}':"
      problems.each do |prob|
        nputs "  #{prob.text}"
        if self.flag? :cert_missing or self.flag? :key_missing \
          or self.flag? :cn_mismatch or self.flag? :san_mismatch \
          or self.flag? :crypto_mismatch or self.flag? :cert_expiring \
          or $opt[:srvexpire]
          # These are all situations where we need a new certificate/key.
          self.flag_set :needs_new_cert
          nputs "Marked for cert renewal."
          #            prob.fixed = true
        end
      end
    end
    nputs "Marked for cert renewal." if self.flag? :needs_new_cert
    nputs "Marked for YAML rewrite." if self.flag? :needs_yaml
    nputs "Marked for eYAML rewrite." if self.flag? :needs_eyaml

    # Update the last_checked, last_status and last_ok fields.
    self.last_checked = $now
    unfixed = problems.count { |p| !p.fixed }
    if unfixed > 0
      self.last_status = 'not ok'
    else
      self.last_status = 'ok'
      self.last_ok = $now
    end

    return problems
  end
end

class ArchiveDir
  # Implements an archive directory, allowing you to move files into and out of
  # it and maintaining numbered backups.

  # Example of how it works:

  # archdir = ArchiveDir.new "/path/to/archive/dir"
  # archdir.put "/path/to/myfile.ext"
  #
  # # The file at /path/to/myfile.ext will be moved to
  # # /path/to/archive/dir/myfile.ext.
  #
  # archdir.put "/other/path/myfile.ext"
  #
  # # In /path/to/archive/dir, myfile.ext will be moved to myfile.ext.1, then
  # # /other/path/myfile.ext will be moved to
  # # /path/to/archive/dir/myfile.ext. Further files named myfile.ext will
  # # cause myfile.ext.1 to be moved to myfile.ext.2, then myfile.ext to
  # # myfile.ext.1, and so forth.
  #
  # archdir.get "/other/path/myfile.ext"
  #
  # # The file at /path/to/archive/dir/myfile.ext will be moved to
  # # /other/path/myfile.ext, and myfile.ext.1 becomes myfile.ext in
  # # /path/to/archive/dir.

  attr_accessor :dir

  private

  def numberedfiles base
    # Return files in @dir that start with the given base, then have a period
    # and one or more digits.
    savedir = Dir.pwd
    Dir.chdir @dir
    startwithbase = Dir.glob "#{base}*"
    numbered = startwithbase.select { |f| f.match("^\Q#{base}\E\.\d+$") }
    Dir.chdir savedir
    return numbered
  end

  def terminal_digits string
    # Given a string that ends in ".\d+$", return the terminal digit string, if
    # any. If there isn't one, return nil.
    string.match("\.(\d+)$") { |md| return md.captures[0] }
    return nil
  end

  public

  def initialize dir = nil
    # Initialize the ArchiveDir object.
    raise ArgumentError.new "Must give a directory to use" unless dir.kind_of? String
    raise FileNotFoundError.new "Directory '#{dir}' does not exist" unless File.exist? dir
    raise RuntimeError.new "File '#{dir}' is not a directory" unless File.ftype(dir) == 'directory'
    @dir = dir
  end

  def put path = nil, archname = nil
    # Given a path to a file, put the file into @dir, renaming it to archname if
    # that parameter is given. If a file of that name already exists, move that
    # file to a numbered suffix, bumping other numbers up if they already
    # exist. Raises exceptions if any number of things go wrong so files don't
    # get overwritten or deleted.
    raise ArgumentError.new "Must give a file path" unless path.kind_of? String
    raise FileNotFoundError.new "File '#{path}' does not exist" unless File.exist? path
    if archname.nil?
      base = File.basename path
    else
      base = File.basename archname
    end
    # Move files to numbered backups in @dir if necessary. First increment the
    # numbered files, if any, then move "#{base}" to #{base}.1". Begin by
    # finding all such "#{base}.\d+" numbered files.
    numbered = (numberedfiles base).sort { |s1, s2| (terminal_digits s1) <=> (terminal_digits s2) }
    # Ensure that if there are no such files, nothing happens.
    if numbered.size > 0
      # Move each of these files to a temporary directory. This ensures that no
      # file will overwrite any other file, in case we have something weird
      # like "myfile.ext.03" and "myfile.ext.3" both existing.
      Dir.mktmpdir("accp") do |tempdir|
        numbered.each do |file|
          FileUtils.mv "#{@dir}/orig", "#{tempdir}/#{orig}"
        end
        # To ensure that there are enough slots, count the elements of
        # 'numbered'. The highest number in the new array of files will end
        # with that count + 1. Starting with the last element in 'numbered',
        # rename the file with that name to one numbered with the next target
        # and decrement the target.
        target = numbered.size + 1
        numbered.reverse_each do |orig|
          FileUtils.mv "#{tempdir}/#{orig}", "#{@dir}/#{base}.#{target.to_s}"
          target -= 1
        end
        # Now, since there were n files and we just renamed them to
        # "#{base}.#{n+1}" down to "#{base}.#{2}", there should be no file called
        # "#{base}.1". If there is, it's a problem.
        raise FileExistsError.new "After renaming the numerical backup files for '#{base}' in '#{@dir}', there is still a '#{base}.1' file" if File.exist? "#{@dir}/#{base}.1"
      end # Dir.mktmpdir
    end # if numbered.size > 0
    # If "#{base}.1" already (or still) exists, that's a problem.
    raise FileExistsError.new "#{@dir}/#{base}.1 already/still exists" if File.exist? "#{@dir}/#{base}.1"
    # Rename "#{base}" to "#{base}.1", if it exists. The only way that could
    # happen is if the file was never there in the first place, i.e. there's
    # never been an attempt to place a file with this name in the archive
    # directory before.
    if File.exist? "#{@dir}/#{base}"
      FileUtils.mv "#{@dir}/#{base}", "#{@dir}/#{base}.1"
    end
    # Finally, move the file from its original path to the archive location.
    FileUtils.mv path, "#{@dir}/#{base}"
  end # def put

  def get path = nil, archname = nil
    # Given a path to a file, find that file in @dir (as archname if that
    # parameter is given) and put it at that path. If there are other backups,
    # decrement their numbers. Raises exceptions if any of a number of things
    # goes wrong. Tries hard not to delete or overwrite anything that already
    # exists.
    raise ArgumentError.new "Must give a file path" unless path.kind_of? String
    raise FileExistsError.new "File '#{path}' already exists" if File.exist? path
    if archname.nil?
      base = File.basename path
    else
      base = File.basename archname
    end
    raise FileNotFoundError.new "File '#{@dir}/#{base}' does not exist" unless File.exist? "#{@dir}/#{base}"
    FileUtils.mv "#{@dir}/#{base}", path
    # Get numbered files.
    numbered = (numberedfiles base).sort { |s1, s2| (terminal_digits s1) <=> (terminal_digits s2) }
    # Don't do anything more if there aren't any numbered backups.
    if numbered.size > 0
      # First move them all to a temporary directory to avoid filename
      # collisions during the upcoming renumbering process.
      Dir.mktmpdir("accg") do |tempdir|
        numbered.each do |orig|
          FileUtils.mv "#{@dir}/#{orig}", "#{tempdir}/#{orig}"
        end
        # Rename the first of those files to "#{@dir}/#{base}", which we just recently
        # moved away, so it can't exist.
        FileUtils.mv "#{tempdir}/#{numbered.shift}", "#{@dir}/#{base}"
        # Starting with 1, rename the rest of the files in 'numbered' to "#{@dir}/#{base}.#{target}".
        target = 1
        numbered.each do |orig|
          FileUtils.mv "#{tempdir}/#{orig}", "#{@dir}/#{base}.#{target.to_s}"
          target += 1
        end
      end # Dir.mktmpdir
    end # if numbered.size > 0
  end # def get

  def exist? base
    # Returns true if "#{@dir}/#{base}" exists and false if not.
    return true if File.exist? "#{@dir}/#{base}"
    return false
  end
end # class ArchiveDir

class CertRecordList
  # Class for a list of CertRecords, basically, along with methods that tell
  # you things about the list.

  include Enumerable

  private

  def move_aside_existing cr
    # Move the existing certificate and key, if any, to $CERT_ARCHIVE_DIR. If
    # there are already files in $CERT_ARCHIVE_DIR by that name, add numerical
    # suffixes. Try not to delete anything.
    archdir = ArchiveDir.new $CERT_ARCHIVE_DIR
    certfile = "#{$PUPPETSRV_CERT_BASE}/#{cr.canonical_certfile}"
    debug_puts 1, "Cert file for '#{cr.cn.to_s}' is '#{certfile}'"
    debug_puts 1, "Cert is a '#{cr.cert.class}'"
    # It's possible the file won't exist, in the case of new certificates.
    if File.exist? certfile and !cr.cert.nil?
      fqcertfile = "#{cr.canonical_certfile_fq}"
      if $opt[:test]
        test_puts "Would archive '#{certfile}' as '#{fqcertfile}'"
      else
        archdir.put certfile, fqcertfile if File.exist? certfile
      end
    end
    keyfile = "#{$PUPPETSRV_CERT_BASE}/#{cr.canonical_keyfile}"
    if File.exist? keyfile and !cr.key.nil?
      fqkeyfile = "#{cr.canonical_keyfile_fq}"
      if $opt[:test]
        test_puts "Would archive '#{keyfile}' as '#{fqkeyfile}'"
      else
        archdir.put keyfile, fqkeyfile if File.exist? keyfile
      end
    end
  end

  def renew_cilogon_user_cert cr
    # Renew a CILogon user cert. Usually called by renew_cilogon_certs.

    ccertfile = cr.canonical_certfile
    ckeyfile = cr.canonical_keyfile
    prev_certfile = "#{$CERT_ARCHIVE_DIR}/#{ccertfile}"
    prev_keyfile = "#{$CERT_ARCHIVE_DIR}/#{ckeyfile}"
    new_certfile = "#{$PUPPETSRV_CERT_BASE}/#{ccertfile}"
    new_keyfile = "#{$PUPPETSRV_CERT_BASE}/#{ckeyfile}"

    Dir.mktmpdir("acccmd") do |tempdir|
      cmd = "osg-user-cert-renew -c '#{prev_certfile}' -k '#{prev_keyfile}' -d '#{tempdir}'"
      cmd += " -v #{cr.requestvo}" if cr.requestvo
      cmd += ' -T' if $opt[:osgtest]
      p12file = nil

      if $opt[:test]
        test_puts "Would do command: #{cmd}"
        p12file = 'testmode.p12'
      else
        system cmd
        # Difficulty: osg-user-cert-renew creates a .p12 file containing the
        # certificate and key, not separate files. It prints the file for the
        # user, but we can't grab the output because we have to allow the
        # script to stay interactive: it's going to ask the user for a
        # passphrase to encrypt the .p12 file with. This is why there's a
        # temporary directory -- we're going to see what .p12 file appears
        # there, as there obviously shouldn't be anything in there beforehand.
        p12files = Set.new(Dir.glob "#{tempdir}/*.p12")
        # If some sort of problem happened and no .p12 file was created, raise
        # an exception.
        raise FileNotFoundError.new "osg-user-cert-renew failed to create a .p12 file in the temp directory" unless p12files.size > 0
        # I don't know how this would happen, but I'm checking just in case
        # more than one .p12 file is there.
        raise RuntimeError.new "Unable to discern which .p12 file osg-user-cert-renew created in the temp directory (#{p12files.to_a.join ', '})" unless p12files.size == 1
        # At this point there should be only one .p12 file.
        p12file = (p12files.to_a)[0]
      end
      # Extract the certificate and key from the PKCS#12 file.
      if $opt[:test]
        puts "Would read '#{p12file}' if it existed, writing certificate to #{new_certfile} and key to #{new_keyfile}"
      else
        p12content = File.read p12file
        good_pw = false
        until good_pw
          begin
            system 'stty -echo'
            print "Enter decryption password for #{p12file}: "
            password = STDIN.gets.chomp
            system 'stty echo'
            puts
            p12 = OpenSSL::PKCS12.new p12content, password
          rescue OpenSSL::PKCS12::PKCS12Error
            puts "Incorrect password"
          rescue
            raise
          else
            good_pw = true
          end
        end
        File.write new_certfile, p12.certificate.to_pem
        File.write new_keyfile, p12.key.to_pem
      end
    end
  end

  def renew_cilogon_san_cert cr
    # Renew a CILogon cert that has a SAN field. Usually called by
    # renew_cilogon_certs.

    ccertfile = cr.canonical_certfile
    ckeyfile = cr.canonical_keyfile
    prev_certfile = "#{$CERT_ARCHIVE_DIR}/#{ccertfile}"
    prev_keyfile = "#{$CERT_ARCHIVE_DIR}/#{ckeyfile}"
    new_certfile = "#{$PUPPETSRV_CERT_BASE}/#{ccertfile}"
    new_keyfile = "#{$PUPPETSRV_CERT_BASE}/#{ckeyfile}"

    Dir.mktmpdir("acccmd") do |tempdir|
      created_certbase = cr.cn.hostname
      created_keybase = "#{created_certbase}-key"
      created_certbase = "#{created_certbase}.pem"
      created_keybase = "#{created_keybase}.pem"
      if cr.cn.service?
        created_certbase = "#{cr.cn.service}-#{created_certbase}"
        created_keybase = "#{cr.cn.service}-#{created_keybase}"
      end
#      created_certfile = "#{tempdir}/#{created_certbase}"
      created_certfile = "#{FileUtils.pwd}/#{created_certbase}"
#      created_keyfile = "#{tempdir}/#{created_keybase}"
      created_keyfile = "#{FileUtils.pwd}/#{created_keybase}"
      # The osg-gridadmin-cert-request command can only accept SAN entries of
      # type 'DNS', and it adds the 'DNS:' to the beginning of them itself, so
      # if we gave it '-a DNS:hostname', it would add a SAN entry that looked
      # like 'DNS:DNS:hostname'. So we are selecting only the 'DNS' SAN entries
      # and giving the command only the hostnames for those.
      sanargs = cr.san.select do |san|
        san.type == 'DNS'
      end.map do |san|
        "-a '#{san.value}'"
      end.join ' '

#      cmd = "osg-gridadmin-cert-request -H '#{cr.cn}' #{sanargs} -d '#{tempdir}'"
      cmd = "osg-gridadmin-cert-request -H '#{cr.cn}' #{sanargs} -d '#{FileUtils.pwd}'"
      cmd += " -v #{cr.requestvo}" if cr.requestvo
      cmd += ' -T' if $opt[:osgtest]
      if $opt[:test]
        test_puts "Would do command: '#{cmd}'"
      else
        system cmd
        raise FileNotFoundError.new "osg-gridadmin-cert-request failed to create '#{created_certfile}'" unless File.exist? created_certfile
        raise FileNotFoundError.new "osg-gridadmin-cert-request failed to create '#{created_keyfile}'" unless File.exist? created_keyfile
      end

      if $opt[:test]
        test_puts "Would move '#{created_certfile}' to '#{new_certfile}'"
      else
        FileUtils.mv created_certfile, new_certfile
      end
      if $opt[:test]
        test_puts "Would move '#{created_keyfile}' to '#{new_keyfile}'"
      else
        FileUtils.mv created_keyfile, new_keyfile
      end
    end
  end

  def renew_cilogon_nosan_certs crs
    # Renew an array of CILogon certs with no SAN fields. Usually called by
    # renew_cilogon_certs.

    # First break up the certs by requestvo.
    crs_by_vo = {}
    crs.each do |cr|
      requestvo = cr.requestvo ? cr.requestvo : '<default>'
      crs_by_vo[requestvo] = [] unless crs_by_vo.key? requestvo
      crs_by_vo[requestvo].push cr
    end
    Dir.mktmpdir("acccmd") do |tempdir|
      crs_by_vo.each do |requestvo, vo_crs|
        if crs_by_vo.keys.size > 1
          if requestvo == '<default>'
            puts "*** Default VO ***"
          else
            puts "*** VO '#{requestvo}' ***"
          end
        end
        # Write a hostfile, one CN per line.
        if $opt[:test]
          test_puts "Would write #{tempdir}/hostfile.txt"
        else
          File.open("#{tempdir}/hostfile.txt", 'w') do |hostfile|
            hostfile.puts vo_crs.map { |cr| cr.cn.to_s }
          end
        end

        cmd = "osg-gridadmin-cert-request -f '#{tempdir}/hostfile.txt' -d '#{tempdir}'"
        cmd += " -v #{requestvo}" if requestvo != '<default>'
        cmd += ' -T' if $opt[:osgtest]
        if $opt[:test]
          test_puts "Would do command: '#{cmd}'"
        else
          system cmd
        end

        # For each cert supposedly written, move it into place, or complain if
        # it wasn't found.
        notfound = []
        vo_crs.each do |cr|
          ccertfile = cr.canonical_certfile
          ckeyfile = cr.canonical_keyfile
          new_certfile = "#{$PUPPETSRV_CERT_BASE}/#{ccertfile}"
          new_keyfile = "#{$PUPPETSRV_CERT_BASE}/#{ckeyfile}"
          created_certbase = cr.cn.hostname
          created_keybase = "#{created_certbase}-key"
          created_certbase = "#{created_certbase}.pem"
          created_keybase = "#{created_keybase}.pem"
          if cr.cn.service?
            created_certbase = "#{cr.cn.service}-#{created_certbase}"
            created_keybase = "#{cr.cn.service}-#{created_keybase}"
          end
          created_certfile = "#{tempdir}/#{created_certbase}"
          created_keyfile = "#{tempdir}/#{created_keybase}"
          if $opt[:test]
            test_puts "Would move #{created_certfile} to #{new_certfile}"
          else
            if File.exist? created_certfile
              FileUtils.mv created_certfile, new_certfile
            else
              notfound.push created_certfile
            end
          end
          if $opt[:test]
            test_puts "Would move #{created_keyfile} to #{new_keyfile}"
          else
            if File.exist? created_keyfile
              FileUtils.mv created_keyfile, new_keyfile
            else
              notfound.push created_keyfile
            end
          end
        end

        if !$opt[:test] and notfound.extra_true?
          raise FileNotFoundError, "osg-gridadmin-cert-request should have created the following files, but failed to:\n#{notfound.join "\n"}"
        end
      end # crs_by_vo.each do
    end # Dir.mktmpdir
  end # def renew_cilogon_nosan_certs

  def renew_cilogon_certs crs = []
    # Given an array of CertRecords of type CILogon that need renewal, let's go
    # do that. This involves:
    #
    # 1. Break them into those that have SAN fields and those that don't.
    #
    #    a. For those that don't have a SAN field,
    #       i. archive existing cert/key files
    #       ii. break list of non-SAN certs down by requestvo
    #       iii. for each requestvo, write a hostfile containing all the CNs
    # that need renewing
    #       iv. run the osg-gridadmin-cert-request command on the hostfile
    #
    #    b. For those that do have a SAN field,
    #       i. archive existing cert/key files
    #       ii. run the osg-gridadmin-cert-request command for each; you can't
    # use a hostfile in this case
    #
    # 2. Put the cert and key files into the proper directory, renaming them
    # from the format the osg-pki-tools script saves it in to the format this
    # script likes.
    #
    # Any existing cert/key files should be moved aside into $CERT_ARCHIVE_DIR,
    # so if there's been a mistake they can be recovered. (Though I suppose
    # they could be recovered via SVN too.)

    # Split them into SAN and non-SAN certs.
    crs_nosan = crs.select { |cr| cr.san.nil? }
    crs_san = crs.select { |cr| !cr.san.nil? }

    # If any of the SAN certs is marked :usercert (all such would be SAN certs
    # because they have an email address in their SAN), split them off into
    # their own array. They're handled differently.
    crs_user = crs_san.select { |cr| cr.flag? :usercert }
    crs_san.reject! { |cr| cr.flag? :usercert }

    savedir = Dir.pwd
    Dir.chdir $PUPPETSRV_CERT_BASE
    # Now deal with each renewal procedure
    crs_user.each do |cr|
      debug_puts 1, "CILogon SAN cert '#{cr.cn.to_s}', a user cert, needs renewal"
      next unless confirm_puts "\nRenew cert '#{cr.cn.to_s}'"
      move_aside_existing cr
      renew_cilogon_user_cert cr
    end
    crs_san.each do |cr|
      debug_puts 1, "CILogon SAN cert '#{cr.cn.to_s}' needs renewal"
      next unless confirm_puts "\nRenew cert '#{cr.cn.to_s}'"
      move_aside_existing cr
      renew_cilogon_san_cert cr
    end
    if crs_nosan.extra_true?
      puts "\nThe following CILogon non-SAN certs need renewal:"
      crs_nosan.each { |cr| puts cr.cn.to_s }
      if confirm_puts "Renew these certs"
        crs_nosan.each { |cr| move_aside_existing cr }
        renew_cilogon_nosan_certs crs_nosan
        crs_nosan.each { |cr| cr.renewed = true }
      else
        crs_nosan.each { |cr| cr.renewed = false }
      end
    end
    Dir.chdir savedir
  end

  def renew_digicert_certs crs = []
    # I don't expect we'll have any of these, since they're deprecated.
    crs.each do |cr|
      puts "DigiCert certificate for '#{cr.cn.to_s}' needs renewal."
      puts "  Skipping, because DigiCert certificates are deprecated."
      puts "  You may want to configure this CN for CILogon instead."
    end
  end

  def renew_incommon_cert cr
    # Renew the given InCommon certificate. Now, the form has started to have
    # an "Auto-Renew" checkbox recently (2017), so I don't know what effect
    # that will have on the renewal process once current certs start to
    # approach their expiration dates. But for now, we'll write this as if
    # we're creating a completely new certificate, which is how it's always
    # happened in the past. Besides, we often have to replace a certificate
    # because its SAN needs to be different or the CN has changed.

    # Create a key and CSR.
    key = OpenSSL::PKey::RSA.new 2048
    csr = OpenSSL::X509::Request.new
    # This is currently (as of 2017) 0 for all known versions.
    csr.version = 0
    # This is important. The subject DN has to be in this format, and it must
    # be parsed into an OpenSSL::X509::Name before you can set it as the CSR's
    # subject.
    csr.subject = OpenSSL::X509::Name.parse "/C=US/ST=Indiana/L=Bloomington/O=Indiana University/OU=Open Science Grid Operations Center/CN=#{cr.cn}"
    # Yes, an RSA public key can be derived from its private key. The reverse
    # is not true. Set the CSR's public key.
    csr.public_key = key.public_key

    # Write the key to a file.
    ckeyfile = cr.canonical_keyfile
    new_keyfile = "#{$PUPPETSRV_CERT_BASE}/#{ckeyfile}"
    if $opt[:test]
      test_puts "Would write '#{new_keyfile}'"
    else
      File.write new_keyfile, key.to_pem
    end

    # If there is a SAN field, attach it to the CSR as an attribute. This is
    # nontrivial. But at least it's a linear (if arcane) process.
    if cr.san
      # We'll need the SAN list as a string, a comma-separated list of
      # TYPE:value pairs.
      sanstring = cr.san.map { |san| san.to_s }.join ', '
      # It sure would be nice if the following were documented somewhere. An
      # X.509 CSR attribute must contain an ASN1 set containing an ASN1
      # sequence containing the SAN as an X.509 extension. Of course,
      # certificates and CSRs are all defined using ASN1 behind the scenes (a
      # CSR is an ASN1 sequence containing the cert data, a sequence containing
      # the signature type designator, and a bit string that is the signature
      # itself; the cert data is a sequence containing the version number and a
      # sequence of data fields; each data field is an ASN1 set containing a
      # sequence of data items), but usually you don't have to interact
      # directly with the ASN1 structure.

      # 472:d=3  hl=2 l=  59 cons:    SEQUENCE
      # 474:d=4  hl=2 l=   9 prim:     OBJECT            :Extension Request
      # 485:d=4  hl=2 l=  46 cons:     SET
      # 487:d=5  hl=2 l=  44 cons:      SEQUENCE
      # 489:d=6  hl=2 l=  42 cons:       SEQUENCE
      # 491:d=7  hl=2 l=   3 prim:        OBJECT            :X509v3 Subject Alternative Name
      # 496:d=7  hl=2 l=  35 prim:        OCTET STRING      [HEX DUMP]:3021821F...

      # At any rate, to add a subjectAltName attribute to an X.509 CSR using
      # OpenSSL, first you make an ExtensionFactory.
      extfact = OpenSSL::X509::ExtensionFactory.new
      # Then you have the factory object create an OpenSSL::X509::Extension
      # containing our 'subjectAltName' extension.
      sanext = extfact.create_extension 'subjectAltName', sanstring, false
      # This is the deep magic here. The attribute requires an ASN1 set
      # containing an ASN1 sequence that contains the extension.
      sanseq = OpenSSL::ASN1::Sequence.new [sanext]
      sanset = OpenSSL::ASN1::Set.new [sanseq]
      # Once we have the proper ASN1 set, create an X.509 "Extension Request"
      # attribute from it. I'm still not sure what you'd do if you had multiple
      # extensions, but we don't, so maybe it'll never come up.
      sanatt = OpenSSL::X509::Attribute.new 'extReq', sanset
      # Add the attribute to the CSR.
      csr.add_attribute sanatt
    end

    # As the last step, sign the CSR with the private key.
    csr.sign key, OpenSSL::Digest::SHA512.new

    # Write the CSR to a file.
    ccsrfile = "#{cr.canonical_prefix_plus_type}_csr.pem"
    new_csrfile = "#{$PUPPETSRV_CERT_BASE}/#{ccsrfile}"
    if $opt[:test]
      test_puts "Would write '#{new_csrfile}'"
    else
      File.write new_csrfile, csr.to_pem
    end

    # Tell the user where to find the web GUI and how to fill it out.
    if $opt[:test]
      test_puts "Here is the generated CSR, but don't actually use it for anything, since this is test mode."
    else
      if cr.san
        formcerttype = 'InCommon Multi Domain SSL (SHA-2)'
      else
        formcerttype = 'InCommmon SSL (SHA-2)'
      end
      puts "InCommon certificates can only be requested via a web GUI.
* Go to this URL:

https://protect.iu.edu/online-safety/tools/ssl-certificates.html

* Log in with 'iucerts' and your IU email address
* Edit address details, removing any that are inaccurate
* Select certificate type '#{formcerttype}'
* Select certificate term '3 years'
* Select server software 'Apache/OpenSSL'
* Copy/paste this CSR:
"
    end
    puts csr.to_pem
    unless $opt[:test]
      puts "
* CN (and SAN if applicable) should be filled in automatically
* If not, click 'Get CN from CSR'
* Check 'Auto renew' and enter 30 days
* Enter a consistent and stored revocation/renewal passphrase

You'll get email in 24-48 hours containing a link to the new certificate from
support@cert-manager.com. Your MUA may put it into your spam folder. Click the
'as X509 Certificate only, Base 64 encoded' link and save the cert locally,
then transfer it to this host. Place it at this path:

#{$PUPPETSRV_CERT_BASE}/#{cr.canonical_certfile}
"

    end
    pause
  end

  def renew_incommon_certs crs = []
    # Given an array of CertRecords for InCommon certificates, renew them
    # all. IU has a contract with InCommon that allows us all to use InCommon
    # certs, but the only way to obtain them is to use a GUI; there's no
    # scriptable way to do it. So after archiving the old certificates, we'll
    # have to create a CSR for each and print the URL to the GUI and the CSR
    # for the user, then wait for them to fill out the web form in their
    # browser. Then move on to the next one, because it can be 24-48 hours
    # before InCommon gets back to the user with the signed cert via email.

    # The certificate is going to be named <underscore_host>_cert.cer, although
    # it will be a PEM-format file as usual, where <underscore_host> is the CN
    # hostname with all dots changed to underscores.

    crs.each do |cr|
      debug_puts 1, "InCommon cert '#{cr.cn.to_s}' needs renewal"
      next unless confirm_puts "\nRenew cert '#{cr.cn.to_s}'"
      # Archive existing certs.
      move_aside_existing cr
      renew_incommon_cert cr
    end
  end

  def renew_internal_certs crs = []
    # So far I haven't had to renew any of these.
  end

  public

  def initialize crs = []
    @crs = []
    raise ArgumentError.new "Array argument required" unless crs.respond_to? :each
    crs.each { |cr| self.push cr }
  end

  def push cr
    # Give this class a push method that works like Array#push.
    raise Argument Error.new "Argument must be a CertRecord (not #{cr.class})" unless cr.kind_of? CertRecord
    @crs.push cr
  end

  def << val
    # Allows you to push a new CertRecord onto the CertRecordList using the <<
    # operator, just as with arrays.
    raise ArgumentError.new "Argument must be a CertRecord (not #{val.class})" unless val.kind_of? CertRecord
    @crs << val
  end

  def each &block
    # Allows you to use the each method to iterate over the CertRecords in this
    # CertRecordList.
    @crs.each &block
  end

  def size
    # Give this class a size method that works like Array#size.
    return @crs.size
  end

  def self.new_from_files config_path = nil, state_path = nil
    # Creates a CertRecordList from config and state files. The file at
    # state_path should have the last_checked, last_status, and last_ok data
    # for each cert, and the file at config_path should have the rest. They're
    # separate because this script should write to state_path but not to
    # config_path.
    crs = []
    if config_path
      # Read the config file data.
      ycerts = YAML.load(File.read config_path)
      ycerts.each do |ycert|
        # Convert each record from the file into a CertRecord.
        cr = CertRecord.new_from_yaml ycert
        crs.push cr
      end
      if state_path
         # Incorporate the data from the state file.
        begin
          state = YAML.load(File.read state_path)
        rescue Errno::ENOENT
          # Handle a "file not found" by creating an empty state file and
          # starting with an empty state hash.
          File.write state_path, (YAML.dump Hash.new)
          state = {}
        end
        # Now that we have the data from the state file, incorporate it into
        # the CertRecords in the array.
        state.each do |cn_str, staterec|
          found = false
          crs.each do |cr|
            if cr.cn.to_s == cn_str
              found = true
              %w(last_checked last_status last_ok).each do |key|
                (cr.method "#{key}=").call staterec[key] if staterec[key]
              end
            end
          end
#          unless found
#            crs.push(CertRecord.new({
#                                      :cn => cn_str,
#                                      :last_checked => staterec['last_checked'],
#                                      :last_status => staterec['last_status'],
#                                      :last_ok => staterec['last_ok'],
#                                    }))
#          end
        end
      end
    end
    self.new crs
  end

  def look_for_trouble
    # Go through @crs and run look_for_trouble on each. Returns the number of
    # problems found and the number of problems fixed.
    #
    # If certs need renewing, it's more efficient to batch them, especially
    # when multiple ones can be requested with one osg-gridadmin-cert-request
    # command. So renewals are batched. Other fixes are done on the
    # fly. CertRecordList level problems:
    #
    # * At least one cert needs to be renewed (no cert at all, or the latest
    # location needs to be renewed)
    #
    problems = []
    @crs.sort { |a, b| a.desc <=> b.desc }.each do |cr|
      next if cr.skipping? or cr.too_recent?
      problems += cr.look_for_trouble
      break if $done
    end
#    @crs.each do |cr|
#      next if cr.skipping? or cr.too_recent?
#    end
    return problems
  end

  def write_state state_path = nil
    # Write the state to the given path (probably $STATEFILE).

    raise ArgumentError.new "State file path must be String" unless state_path.kind_of? String
    state = Hash.new { |hash, key| hash[key] = {} }
    self.each do |cr|
      d = cr.cn.to_s
      %w(last_checked last_status last_ok).each do |key|
        state[d][key] = (cr.method key.to_sym).call
      end
    end
    File.write state_path, (YAML.dump state)
  end

  def fix_things
    # Fix the problems that look_for_trouble found.

    # Obviously the most common problem is that something has been marked with
    # the :needs_new_cert flag. We'll have to group those into their cert
    # types. CILogon certs, for one thing, can be batch-renewed. And now that
    # we're running on the same server that's doing the requesting, we can just
    # do it.
    crs_to_renew = @crs.select { |cr| cr.flag? :needs_new_cert }
    # If something's wrong with the YAML, and if we're paying attention to that
    # due to the -2 option, don't attempt to renew the cert, because with the
    # YAML wrong it may have no place to go or may be going to the wrong place.
    if $opt[:yaml]
      crs_to_renew.reject! { |cr| cr.flag? :needs_yaml }
    end
    $RENEW_TYPE.keys.each do |cert_type|
      crs_of_this_type_to_renew = crs_to_renew.select { |cr| cr.type == cert_type }
      (self.method $RENEW_TYPE[cert_type]).call crs_of_this_type_to_renew
    end

    # If the -2 option was used on the command line, there exists the
    # possibility that the Puppet Hiera file might not exist, might not define
    # a resource for this certificate, or might disagree on particulars like
    # destination path, ownerships and permissions, in which case it would have
    # been flagged. Look for that flag and handle it now. If the -2 option
    # wasn't used, inform the user that they will have to manage the Puppet
    # resources for the certificate by hand.
    if $opt[:yaml]
      crs_to_fix_hiera = @crs.select { |cr| cr.flag? :needs_yaml }
      crs_to_fix_hiera.each do |cr|
        cr.rewrite_hiera
      end
    else
      crs_to_check = crs_to_renew.select { |cr| cr.renewed }
      if crs_to_check.size > 0
        puts "You may want to check the Hiera host files:"
        paths = Set.new
        crs_to_check.each do |cr|
          cr.targets.each do |t|
            short = (t.host.split '.', 2).first
            paths.add "#{$PUPPETSRV_HIERA_HOST_BASE}/#{short}.yaml"
          end
        end
        paths.each { |p| puts "  #{p}" }
      end
    end

    # If the -3 option was used on the command line, there exists the
    # possibility that the key doesn't match the one stored in the Puppet Hiera
    # file, encrypted with eYAML, in which case it would have been
    # flagged. That possibility becomes a certainty if we just renewed the
    # cert. Look for that flag (or the case where we just renewed) and handle
    # it now. If the -3 option wasn't used, inform the user that they will have
    # to manage the key by hand.
    if $opt[:eyaml]
      crs_to_fix_eyaml = @crs.select { |cr| cr.flag? :needs_eyaml }
      crs_to_fix_eyaml.each do |cr|
      end
    else
      crs_to_check = crs_to_renew.select { |cr| cr.renewed }
      if crs_to_check.size > 0
        puts "You will probably have to sudo eyaml edit the Hiera host files"
        puts "to add the new key:"
        paths = Set.new
        crs_to_check.each do |cr|
          cr.targets.each do |t|
            short = (t.host.split '.', 2).first
            paths.add "#{$PUPPETSRV_HIERA_HOST_BASE}/#{short}.yaml"
          end
        end
        paths.each { |p| puts "  #{p}" }
      end
    end
  end

end

###############################################################################
# Global methods
###############################################################################

def parse_options
  # Parse the command-line options, setting keys in $opt based on what they
  # are.

  # Specify a default value of false so we don't get nil or errors when
  # referencing an unset key.
  $opt = Hash.new nil
  $opt[:debug] = 0

  parser = OptionParser.new(1) do |p|
    p.program_name = 'autocertcheck.rb'
    p.version = $VERSION
    p.release = $RELEASE
    p.separator '---'
    p.summary_indent = '  '
    p.summary_width = 20
    p.banner = "Usage: #{$0} [<options>]"
    p.on('-2', '--yaml', :NONE, 'Attempt to write YAML files on Puppet server') { |v| $opt[:yaml] = true }
    p.on('-3', '--eyaml', :NONE, 'Attempt to write eYAML files on Puppet server (implies -2)') { |v| $opt[:eyaml] = true; $opt[:yaml] = true }
    p.on('-c', '--cn=<CN>', :REQUIRED, 'Ignore all hosts but those with this Common Name') { |v| $opt[:cn] = v }
    p.on('-d', '--debug=<LEVEL>', :REQUIRED, 'Debug output level (default = 0)') { |v| $opt[:debug] = v.to_i }
    p.on('-f', '--force', :NONE, 'Force processing; ignore recent OKs') { |v| $opt[:force] = true }
    p.on('-i', '--inquire', :NONE, 'Ask for confirmation before each change') { |v| $opt[:inquire] = true }
    p.on('-l', '--list', :NONE, 'Just list the keys this script knows about') { |v| $opt[:list] = true }
    p.on('-o', '--osgtest', :NONE, 'In actions that use the OSG PKI scripts, run them in test mode') { |v| $opt[:osgtest] = true }
    p.on('-s', '--skip=<CN>', :REQUIRED, 'Ignore hosts with this Common Name') { |v| $opt[:skip] = v }
    p.on('-t', '--test', :NONE, 'Toggles test mode (show commands to run but do nothing)') { |v| $opt[:test] = true }
    p.on('-x', '--srvexpire', :NONE, 'Perceive certs on server as expired (force renew)') { |v| $opt[:srvexpire] = true }
  end

  begin
    parser.parse!
  rescue OptionParser::InvalidOption
    pfputs $!.message
  end
end

def handle_signal signal
  nputs "Received signal #{signal} ... exiting soon"
  $done = true
end

def main_init
  ["INT", "QUIT", "TERM"].each do |signame|
    Signal.trap signame, proc { handle_signal signame }
  end
  parse_options
  return CertRecordList.new_from_files config_path = $CONFIG,
                                       state_path = $STATEFILE
end

def debug_puts lvl, string
  # Does a puts, with a DEBUG prefix, but only if $opt[:debug] is >= lvl.
  nputs "DEBUG>>> #{string}" if $opt[:debug] >= lvl
end

def test_puts string
  # Does a puts, with a TEST prefix.
  nputs "TEST>>> #{string}"
end

def nputs string
  # Just does a puts, with newline_if_needed beforehand to cancel the effect of
  # progress_puts, if any.
  newline_if_needed
  puts string
end

def progress_puts msg
  # Prints whatever it's given, with a progress prefix, but only if it's been
  # more than $PROGRESS_TIMEOUT seconds since $last_progress.
  now = Time.new.to_i
  if (now - $last_progress) > $PROGRESS_TIMEOUT
    print " "*$progress_columns + "\r"
    the_string = "(... progress ...) #{msg}"
    $progress_columns = the_string.size
    print the_string + "\r"
    $last_progress = now
  end
end

def newline_if_needed
  unless $progress_columns.zero?
    print " "*$progress_columns + "\n"
    $progress_columns = 0
  end
end

def confirm_puts msg
  # Prints the message, then asks for y/n confirmation. Returns true if the
  # user answers Y, and false otherwise. Default is N. If $opt[:inquire] is
  # false, or the key doesn't exist, does nothing but returns true.
  return true unless $opt[:inquire]
  result = nil
  while result.nil?
    break if $done
    print "#{msg} (y/N)? "
    answer = $stdin.gets
    break if $done
    if answer.nil?
      answer = 'n'
      nputs
    else
      answer.chomp!
      if answer.empty?
        answer = 'n'
      else
        answer = answer[0..0].downcase
      end
    end
    if answer == 'y'
      result = true
    elsif answer == 'n'
      result = false
    else
      nputs "We need a 'y' or 'n' here."
    end
  end
  return result
end

def pause
  # Just pause and wait for the user to hit Enter/Return.
  nputs "Press Return to continue."
  $stdin.gets
end

###############################################################################
# Main
###############################################################################

certs = main_init
problems = certs.look_for_trouble
if problems.count { |p| !p.fixed } == 0
  nputs "No problems found."
else
  nputs "#{problems.count} problems found, #{problems.count { |p| p.fixed }} problems fixed."
  certs.fix_things
end
END {
  certs.write_state state_path = $STATEFILE
}

# This is going to be a more major rewrite than I thought. We're going to move
# entirely to using Puppet. We're even going to request certs on the Puppet
# server. The cert server is still going to be used for signing SSH host certs,
# though, and probably for certs signed by the GOC local CA, but neither of
# those things concerns this script. The files on the Puppet server are all in
# one place with one filename scheme and one user/group/mode setting, so I
# don't have to worry about target locations with weird variant filenames,
# different user/group/mode settings, etc. That's for Puppet to deal with, not
# this script.

# This limits the different complicated possibilities that this script has to
# deal with. For things to be perfect, we must have, on the Puppet server:
#
# 1. A certificate that isn't expired/expiring soon
# 2. A key that cryptographically matches that certificate
#
# Hence there are two files, meaning that what can go wrong is more limited
# than it used to be. True, either of them can be deleted or replaced with
# another, and in addition to that, the certificate can expire. So here are the
# possible states of this system:
#
# * Everything hunky-dory (and in all other cases all is OK with noted exceptions)
# * Cert expiring
# * One or both files are missing
# * One or both files have been replaced, possibly with unmatching certs/keys,
#   or with files that aren't even certs/keys
# * Some combination of these
# * No files at all (new cert that hasn't been requested yet)
#
# Additionally, the plan for the future is to not even store the keys in
# plaintext. That would mean either storing the encryption key here in this
# script or typing it every time this script is run. But they already aren't
# checked in to version control on the Puppet server, instead being stored
# encrypted in the Puppet/Hiera YAML files using eYAML. The keys are currently
# in plaintext on the Puppet server in the development environment, but are not
# checked into version control. The goal is eventually to store them encrypted
# even there.
#
# So the procedure that this script should probably go through is this:
#
# * Read the certificate and key files
# * Discard from consideration anything that is not a certificate/key
# * Discard the cert from consideration if its CN or SAN doesn't match expectations
# * Discard the cert from consideration if it's expired/expiring
# * If there is still a cert and key under consideration, see if they match,
#   and discard them if they don't
# * If we don't have a matching cert and key at this point, do a cert request
