#!/bin/env ruby

# build_munin_conf.rb -- rebuild all the Munin node config files
# Tom Lee <thomlee@iu.edu>
# Begun 2017/02/15
# Last modified 2017/04/06

# There were two problems with Munin configuration, but they weren't that
# bad. We were doing OK.
#
# 1. There was no way to globally configure a module -- any settings change to
# a module had to be done in every node individually.
#
# 2. The configuration files had to be edited by hand -- there was no way to
# automatically disable monitoring on a machine that was offline or enable
# monitoring on a new machine.
#
# Then with the OS update of January 2017, a third problem appeared.
#
# 3. Munin could no longer contact any hosts, even though one could telnet from
# the Munin server to any of the hosts and manually read the Munin plugin
# information. It turned out the reason why was that the "address" setting for
# each node had stopped accepting hostnames and could now only accept IP
# addresses. Munin used to be able to look up host names in DNS and now
# mysteriously couldn't anymore. I didn't want to manually edit 100+ config
# files to replace the hostname with an IP address.
#
# So I wrote this script instead to solve all three problems. Configured with a
# YAML file, this script reads global and node-specific settings and writes all
# the Munin node configuration files.

###############################################################################
# Requires

require 'ftools'
require 'optparse'
require 'resolv'
require 'yaml'

###############################################################################
# Settings

# Program name
$PROG_NAME = 'build_munin_conf.rb'

# Program version
$PROG_VERSION = '0.1'

# Program release
$PROG_RELEASE = 'beta'

# Munin directory
$MUNIN_DIR = '/usr/local/munin'

# Template directory
$TEMPLATE_DIR = "#{$MUNIN_DIR}/templates"

# Config file
$CONFIG_FILE = "#{$MUNIN_DIR}/etc/conf.yaml"

# Config directory to write files to
$DEST_CONFIG_DIR = "#{$MUNIN_DIR}/conf.d"

# Munin update lock file -- munin-update puts this here when it runs
$MUNIN_UPDATE_LOCK = '/var/run/munin/munin-update.lock'

###############################################################################
# Modules

# None at present

###############################################################################
# Classes

class ConfigError < RuntimeError
  # Allows more specific error messages.
end

###############################################################################
# Global methods

def handle_options
  opt = Hash.new
  parser = OptionParser.new(1) do |p|
    p.program_name = $PROG_NAME
    p.version = $PROG_VERSION
    p.release = $PROG_RELEASE
    p.separator '---'
    p.summary_indent = '  '
    p.summary_width = 18
    p.banner = "Usage: #{$0} [<options>]"
    p.on('-b', '--bridge', :NONE, 'Bridge: read old config files and convert to new format') { |v| opt[:bridge] = 1 }
    p.on('-d', '--debug', :NONE, 'Debug mode (extra output)') { |v| opt[:debug] = 1 }
  end
  begin
    parser.parse!
  rescue OptionParser::InvalidOption
    puts $!.message
    exit
  end
  return opt
end

def read_config
  # Read the config file and do some syntax checking.
  data = YAML.load(File.read $CONFIG_FILE)
  if data.key? 'global' and !data['global'].nil?
    unless data['global'].kind_of? Hash
      raise ConfigError.new "#{$CONFIG_FILE}: global must be mapping"
    end
  end
  if data.key? 'flag' and !data['flag'].nil?
    unless data['flag'].kind_of? Hash
      raise ConfigError.new "#{$CONFIG_FILE}: flag must be mapping"
    end
    data['flag'].each do |key, value|
      unless value.nil? or value.kind_of? Hash
        raise ConfigError.ne "#{$CONFIG_FILE}: flag[#{key}] must be mapping"
      end
    end
  end
  if data.key? 'flags' and !data['flag'].nil?
    unless data['flags'].kind_of? Hash
      raise ConfigError.new "#{$CONFIG_FILE}: flags must be mapping"
    end
    value_seen = Hash.new(0)
    data['flags'].each do |flag, flag_config|
      unless flag_config.kind_of? Hash
        raise ConfigError.new "#{$CONFIG_FILE}: flags[#{flag}] must be mapping"
      end
      ['label', 'category', 'value'].each do |key|
        unless flag_config.key? key
          raise ConfigError.new "#{$CONFIG_FILE}: flags[#{flag}] must have '#{key}'"
        end
      end
      if value_seen["#{flag_config['category']}:#{flag_config['value']}"] > 0
        raise ConfigError.new "#{$CONFIG_FILE}: flags[#{flag}] has duplicate category/value"
      end
      value_seen["#{flag_config['category']}:#{flag_config['value']}"] += 1
    end
  end
  if data.key? 'nodes' and !data['nodes'].nil?
    unless data['nodes'].kind_of? Hash
      raise ConfigError.new "#{$CONFIG_FILE}: nodes must be mapping"
    end
    data['nodes'].each do |node, node_config|
      if node_config.key? 'flags' and !node_config['flags'].nil?
        unless node_config['flags'].kind_of? Array
          raise ConfigError.new "#{$CONFIG_FILE}: for node '#{node}', flags must be sequence"
        end
        value_seen = Hash.new(0)
        node_config['flags'].each do |flag|
          unless data.key? 'flags'
            raise ConfigError.new "#{$CONFIG_FILE}: node '#{node}' has flags, but there is no global 'flags' mapping"
          end
          unless data['flags'].kind_of? Hash
            raise ConfigError.new "#{$CONFIG_FILE}: node '#{node}' has flags, but there global 'flags' is not a mapping"
          end
          unless data['flags'].key? flag
            raise ConfigError.new "#{$CONFIG_FILE}: node '#{node}' references undefined flag '#{flag}'"
          end
          if value_seen["#{data['flags'][flag]['category']}"] > 0
            raise ConfigError.new "#{$CONFIG_FILE}: node '#{node}' has multiple flags in an exclusive category"
          end
          value_seen["#{data['flags'][flag]['category']}"] += 1
        end
      end
    end
  end
  return data
end

def debug_puts str
  return unless $opt[:debug]
  puts "DEBUG: #{str}"
end

def wait_for_munin_update_lock
  # If there's a $MUNIN_UPDATE_LOCK in place, wait for it to go
  # away. It means Munin is updating right now, and we don't want to
  # run while that's happening.
  if File.exist? $MUNIN_UPDATE_LOCK
    debug_puts "Waiting for munin-update lockfile to clear ..."
    sleep 1
  end
  while File.exist? $MUNIN_UPDATE_LOCK
    sleep 1
  end
end

def compare_values a, b
  a = a.to_i if a =~ /^\d+$/
  b = b.to_i if b =~ /^\d+$/
  result = a <=> b
  return result
end

def recursive_set h, dotkey, value
  if dotkey.include? '.'
    first, rest = dotkey.split '.', 2
    h[first] = Hash.new unless h.key? first
    recursive_set h[first], rest, value
  else
    h[dotkey] = value
  end
end

def bridge_old_files conf
  global = recursive_join conf['global'], '.'
  olddir = "#{$MUNIN_DIR}/conf.old"
  conf['nodes'] = Hash.new unless conf.key? 'nodes'
  d = Dir.open olddir
  d.sort.each do |file|
    next if file.start_with? '.'
    next unless file =~ /^[0-9][0-9]-/
    next if file[0..1].to_i < 4
    text = File.read "#{olddir}/#{file}"
    lines = text.split "\n"
    headers = lines.select { |t| t =~ /^\[.*\]$/ }
    if headers.size != 1
      raise ConfigError.new "#{olddir}/#{file}: Must have one and only one [header;line]"
    end
    header = headers[0]
    group, host = header[1..-2].split ';'
    flags = []
    if group == 'Production_Servers'
      flags = %w(phys prod)
    elsif group == 'Production_VMs'
      flags = %w(vm prod)
    elsif group == 'Development_Servers'
      flags = %w(phys dev)
    elsif group == 'Development_VMs'
      flags = %w(vm dev)
    elsif group == 'ITB_VMs'
      flags = %w(vm itb)
    elsif group == 'Support_VMs'
      flags = %w(vm staff)
    else
      flags = %w(vm int)
    end
    conf['nodes'][host] = Hash.new unless conf['nodes'].key? host
    conf['nodes'][host]['flags'] = flags
    hconf = Hash.new(nil)
    lines.each do |t|
      next if t.start_with? '['
      next if t.strip == ''
      next if t.strip.start_with? '#'
      key, value = t.lstrip.split /\s+/, 2
      hconf[key] = value
    end
    hconf.each do |key, value|
      setit = false
      next if key == 'address'
      if global.key? key
        if compare_values(global[key], value) != 0
          setit = true
        end
      else
        setit = true
      end
      if setit
        if value.kind_of? String
          if value =~ /^\d+$/
            value = value.to_i
          end
        end
        recursive_set conf, "nodes.#{host}.#{key}", value
      end
    end
  end
  File.copy "#{$CONFIG_FILE}", "#{$CONFIG_FILE}.bak"
  File.open("#{$CONFIG_FILE}", "w") { |f| f.puts(YAML.dump conf) }
end

def recursive_join data, sep, accum = Hash.new, path = Array.new
  if data.kind_of? Hash
    data.each do |key, value|
      recursive_join value, sep, accum, path + key.to_a
    end
  else
    # YAML turns 'yes' and 'no' to true and false, but Munin only
    # understands 'yes' and 'no'.
    if data == true
      data = 'yes'
    elsif data == false
      data = 'no'
    end
    accum[path.join sep] = data
  end
  return accum
end

def augment_data nodedata, conf, short
  data = Hash.new
  # Global settings override Munin defaults.
  if conf.key? 'global' and conf['global'].kind_of? Hash
    conf['global'].each do |key, value|
      data[key] = Marshal.load(Marshal.dump value)
    end
  end
  # Flag settings override Munin defaults and global settings.
  if nodedata.key? 'flags' and nodedata['flags'].kind_of? Array and conf.key? 'flag' and conf['flag'].kind_of? Hash
    nodedata['flags'].each do |flag|
      next unless conf['flag'].key? flag and conf['flag'][flag].kind_of? Hash
      conf['flag'][flag].each do |key, value|
        data[key] = Marshal.load(Marshal.dump value)
      end
    end
  end
  # Node settings override all others.
  nodedata.each do |key, value|
    next if key == 'flags'
    data[key] = Marshal.load(Marshal.dump value)
  end
  return data
end

def best_ip host
  records = Array.new
  Resolv::DNS.open do |resolver|
    results = resolver.getresources host, Resolv::DNS::Resource::IN::A
    records += results
  end
  if records.size == 0
    raise ConfigError.new "Host '#{host}' not found in DNS"
  end
  return records[0].address.to_s
end

def handle_nodes conf = Hash.new
  return unless conf.key? 'nodes'
  # Add 'address' to each node (do this now rather than as part of the
  # loop below so that if any hostname isn't found in DNS, that
  # exception gets raised and the script gets stopped before we delete
  # any files).
  conf['nodes'].each do |short, nodedata|
    # Skip any nodes with 'disable' set to true, since we won't be
    # writing files for them.
    next if conf['nodes'][short].key? 'disable' and conf['nodes'][short]['disable']
    conf['nodes'][short]['address'] = best_ip(short + '.goc')
  end
  # Delete all the files in $DEST_CONFIG_DIR whose names start with
  # two digits and a hyphen, unless those two digits are a number with
  # value less than 10. Files whose names don't start with "NN-" and
  # files whose initial number is less than 10 (the base config files)
  # are left alone.
  Dir.open("#{$DEST_CONFIG_DIR}") do |dir|
    dir.each do |file|
      # This will ignore ., .., README, etc.
      next unless file =~ /^\d\d-/
      # This will ignore the base config files.
      next if file[0..1].to_i < 10
      # Otherwise, delete the file.
      File.unlink "#{$DEST_CONFIG_DIR}/#{file}"
    end
  end
  # Write a config file for each node in conf.
  conf['nodes'].each do |short, nodedata|
    # Skip any nodes with 'disable' set to true.
    next if conf['nodes'][short].key? 'disable' and conf['nodes'][short]['disable']
    # Assemble the group from the flag labels.
    group = nodedata['flags'].sort { |a, b| conf['flags'][b]['value'] <=> conf['flags'][a]['value'] }.map { |f| conf['flags'][f]['label'] }.join '_'
    # Calculate a file number by adding the flag values.
    number = nodedata['flags'].map { |f| conf['flags'][f]['value'] }.reduce(:+)
    # Assemble the filename and open the file.
    filename = sprintf("%02d-%s", number, short)
    File.open("#{$DEST_CONFIG_DIR}/#{filename}", "w") do |file|
      file.puts "# Munin configuration file for #{short}."
      file.puts "# Editing this file is not recommended."
      file.puts "# Instead, edit /usr/local/munin/etc/conf.yaml,"
      file.puts "# then run /usr/local/munin/bin/build_munin_conf.rb."
      file.puts "# See /usr/local/munin/etc/README for details."
      file.puts
      file.puts "[#{group};#{short}]"
      data = recursive_join((augment_data nodedata, conf, short), '.')
      data.keys.sort.each do |key|
        file.puts "  #{key} #{data[key]}"
      end
    end
  end
  
end

###############################################################################
# Main program

$opt = handle_options
$conf = read_config
wait_for_munin_update_lock
if $opt[:bridge]
# Commented out so you don't do this accidentally.
#  bridge_old_files $conf
else
  handle_nodes $conf
end
