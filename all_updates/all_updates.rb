#!/usr/bin/env ruby
# Encoding: utf-8

# all_updates.rb: an attempt to rewrite my OS update script in Ruby with
# Curses support

# Tom Lee <thomlee@iu.edu>
# Begun 2017-04-25
# Last modified 2018-03-06

# As with the Perl version, this script exists because of the sheer number of
# OS updates I must do. The killer is, as always, the wait time: every delay is
# multiplied by the number of systems being updated, and there is a delay
# whenever I have to wait for one step to finish before initiating the next
# one. This script exists to deal with the routine tasks so I have time to deal
# with the unusual variations that inevitably occur.

# Also, as before, I don't want people in general to know this script
# exists. When Soichi was working with the group, every time he found out I'd
# written a script to make my job easier, he would begin to request that I make
# it available to the whole group in some way, meaning that I would then have
# to support it and answer questions about why it didn't work in some way it
# was never intended to work, etc. This script is not intended for anyone to
# use who is not a systems administrator for the High Throughput Computing
# Group. I make no apologies. I wrote this for myself to use. If you want to
# adapt it for some other situation, good luck to you, but I will not be
# supporting you.

# I have tried to use Ansible for OS updates, in case you get that bright
# idea. It doesn't do what I need it to do. When Ansible can show you the full
# output of a command in a terminal window and give you a shell prompt right
# after, in the same environment, so you can check things out or fix whatever
# problems appeared in the output (which you can scroll up to read), that's
# when I might consider using Ansible to replace this script. But Ansible can't
# be that interactive; it can capture a command's standard output and put it in
# a file or display it to the screen, but it can't give you a shell prompt on
# that remote machine.

# Linguistic note: "system" is the word I've chosen to refer to a physical or
# virtual machine, a thing that can have an operating system installed on
# it. Referring to systems as "hosts," as in "network hosts," was getting
# confusing because of the other meaning of "host," as in "virtualization host"
# (as opposed to a guest). We'll still refer to jump hosts, VPN hosts, LDAP
# hosts, VM hosts, etc., and to hostnames, but a machine on our network will be
# called a "system." In Ruby (as in Perl) there is a "system" statement,
# though, so we need to be careful not to name a variable "system" to avoid
# syntax errors. The symbol :system is OK, as are object instance methods named
# obj.system.

# This script has a systemdata.yaml file that governs what it does with each
# system. Each system has a mapping from its shortname to a mapping of
# data. The keys in each system's mapping:
#
# day (required, string): which day this host updates on; allowed values are:
#   itb: ITB system; updates on 3rd Tuesday of month
#   int: Internal system; updates on day before itb (3rd Monday of month unless
#        month starts on Tuesday; then 2nd Monday)
#   prod: Production system; updates on 4th Tuesday of month
#   none: Updates disabled (setting 'skip' is a better way to do this, as it
#         allows for an explanation)
#
# vmhost (required, string): shortname of this VM's virtualization host, or:
#   _ii: VM is on IU Intelligent Infrastructure (we don't update the VM host)
#   _phys: System is a physical machine, not a VM (no VM host to update)
#
# is_vmhost (optional, string): system is a virtualization host; value is one
#                               of the following:
#   kvm: system is a KVM/qemu/libvirt host
#   vmw: system is a VMWare host
#
# group (optional, string): LVS update group this host is in, if any; typically
#                           one of the following:
#   group1
#   group2
#
# distro (optional, string): distro this host runs; allowed values are:
#   5: RHEL 5
#   6: RHEL 6
#   c6: CentOS 6
#   c7: CentOS 7
#
# skip (optional, string): don't update this system; value is human-readable
#                          explanation of why and whether this is permanent
#
# i386 (optional, Boolean): system has 32-bit version of distro; this is going
#                           away, but there are still a few
#
# jumphost (optional, Boolean): system is a jump host (doesn't permit sudo)
#
# lvs (optional, Boolean): system is an LVS server and can be sent LVS commands
#
# noncompliant (optional, Boolean): doesn't follow GOC policy and must be
#                                   handled manually
#
# updatetest (optional, Boolean): system is for testing updates (NYI)
#
# vpnserver (optional, Boolean): system is a VPN server; when rebooting this
#                                system, we must use a jumphost as a proxy, one
#                                that isn't being updated during this run
#
# yum_internal (optional, Boolean): system is an internal distro mirror that
#                                   will need to be reposynced on internal day
#
# staff (optional, Boolean): system is a staff vm (like thomlee, steige,
#                            mvkrenz, echism, kagross, rquick, etc.); this item
#                            actually has no effect on how it is treated, but
#                            it is here for additional information
#
# nas (optional, Boolean): system is a NAS device; this item is not actually
#                          used at this time
#
# time (optional, string): indicates time of day before which the host should
#                          not be updated; currently there are no hosts like
#                          this, but its format is HH:MM_TZ, where TZ is a time
#                          zone string locating the time zone file in the
#                          tzdata directory (typically /usr/share/zoneinfo),
#                          for example:
#   12:00_America/Indiana/Indianapolis: won't update before noon in Indy
#   12:00_America/Los_Angeles: won't update before noon in LA

require 'curses'
require './cursesui'
require 'fileutils'
require 'net/dns'
require 'net/ldap'
require 'optparse'
require 'rubygems'
require 'set'
require './task'
require './tasklist'
require 'thread'
require 'time'
require './tmux'
require 'yaml'

###############################################################################
# Settings
###############################################################################

# Path to directory containing $systemdatafile and $savefile
$dirpath = '/home/thomlee/all_updates'

# File containing system data
$systemdatafile = "#{$dirpath}/systemdata.yaml"

# LDAP hosts for lookups
$ldaphosts = %w(ds1.grid.iu.edu)

# DNS cache file
$dnscachefile = "/opt/var/cache/dns/dns_cache.yaml"

# Save file for tasklist
$savefile = "#{$dirpath}/all_updates_save.yaml"

# TTL for DNS entries that aren't found
$ttl_undef = 86400

# Name of program
$PROG_NAME = 'all_updates.rb'

# Version of program
$PROG_VERSION = '0.3'

# Release of program
$PROG_RELEASE = '2'

# Delay times for various types of tasks
$tasktime =
  {
    :complete => 0,
    :shutdown => 1,
    :ssh_test => 10,
    :allvmsdown => 60,
    :osupdate => 120,
    :grub_pause => 240,
    :LVS => 300,
    :reposync => 900,
    :afternoon => 99999,
  }

# Maximum number of tmux windows that may be open at once
$max_windows = 72

# Delay before retrying a failed task, in floating-point seconds
$retry_delay = 10.0

###############################################################################
# Classes
###############################################################################

class String
  def wrap width
    # "Wraps" the words in a string to fit within the given width, not breaking
    # words up if possible. (If there is a word longer than width, it will be
    # broken.)
    result = ""
    column = 0
    # Break the string up into paragraphs and words.
    paragraphs = self.split "\n"
    paragraphs.each do |paragraph|
      if paragraph == ''
        result += "\n"
        column = 0
      else
        words = paragraph.split(/\s+/)
        words.each do |word|
          # If the word would go off the end of the string, add a CRLF.
          if column + word.size > width
            # Add a newline to result, unless the column is already 0 (long
            # word!).
            unless column == 0
              result += "\n"
            end
            # Make sure the column is 0.
            column = 0
          end
          # Add the word. Now, if the word is long or the width is short, we
          # might have to break the word. Only do this if column is 0, but if the
          # word is that long compared to the width, we'd already have added the
          # previous CRLF.
          loop do
            # If word.size <= width, this will cause head to be the entire word:
            head = word[0..(width - 1)]
            # If word.size == width, this will cause word to be "". If word.size
            # > width, this will cause word to be nil:
            word = word[width..-1]
            result += head
            column += head.size
            if word and word.size > 0
              # There's more to go.
              result += "\n"
              column = 0
            else
              break
            end
          end # of word
          # Add a space to get ready for the next word.
          result += ' '
          column += 1
        end
      end # of paragraph
      # The last word would have left a trailing space.
      result.sub!(/ $/, '')
      # Add a CRLF to get ready for the next paragraph.
      result += "\n"
      column = 0
    end # of last paragraph
    # The last paragraph would have left a trailing newline.
    result.sub!(/\n$/, '')
    return result
  end # of method
end # of class

class System
  # Data about a system, in object form. See comments at beginning of script
  # for information on what should be in these attributes.

  attr_reader :name, :day, :vmhost, :is_vmhost, :group, :distro, :skip, :i386,
              :jumphost, :lvs, :noncompliant, :updatetest, :vpnserver,
              :yum_internal, :time, :hasvpnserver, :staff, :nas

  def initialize arg
    [:name, :day, :vmhost, :is_vmhost, :group, :distro, :skip, :i386,
     :jumphost, :lvs, :noncompliant, :updatetest, :vpnserver, :yum_internal,
     :time, :hasvpnserver, :staff, :nas].each do |attr|
      if arg.key? attr
        # Call writer methods for each attribute. Those not listed in
        # attr_accesor above must have a writer method defined below; these are
        # for value checking.
        (self.method "#{attr}=").call arg[attr]
      end
      if arg.key? :afternoon
        self.time = '12:00_America/Indiana/Indianapolis'
      end
    end
  end

  def name= value = nil
    # Set the system name.

    raise ArgumentError.new "#{__method__}: Must be a String (is a #{value.class})" unless value.kind_of? String
    @name = value
  end

  def day= value = 'none'
    # Set the update day code.

    raise ArgumentError.new "#{__method__}: Allowed values are 'itb', 'int', 'prod', and 'none'" unless %w(itb int prod none).include? value
    @day = value
  end

  def vmhost= value = nil
    # Set the vmhost field.

    raise ArgumentError.new "#{__method__}: Must be a String (is a #{value.class})" unless value.kind_of? String
    raise ArgumentError.new "#{__method__}: Must be short hostname, '_ii', or '_phys'" if value[0] == '_' and (value != '_ii' and value != '_phys')
    @vmhost = value
  end

  def is_vmhost= value = nil
    raise ArgumentError.new "#{__method__}: Allowed values are 'kvm' and 'vmw' (or nil)" unless value == 'kvm' or value == 'vmw' or value.nil?
    @is_vmhost = value
  end

  def group= value = nil
    raise ArgumentError.new "#{__method__}: Must be a String (is a #{value.class})" unless value.kind_of? String or value.nil?
    @group = value
  end

  def distro= value = nil
    raise ArgumentError.new "#{__method__}: Allowed values are '5', '6', 'c6', and 'c7'" unless %w(5 6 c6 c7).include? value
    @distro = value
  end

  def skip= value = nil
    raise ArgumentError.new "#{__method__}: Must be a String (is a #{value.class})" unless value.kind_of? String or value.nil?
    @skip = value
  end

  def i386= value = nil
    raise ArgumentError.new "#{__method__}: Must be true or false" unless value == true or value == false or value.nil?
    @i386 = value
  end

  def jumphost= value = nil
    raise ArgumentError.new "#{__method__}: Must be true or false" unless value == true or value == false or value.nil?
    @jumphost = value
  end

  def lvs= value = nil
    raise ArgumentError.new "#{__method__}: Must be true or false" unless value == true or value == false or value.nil?
    @lvs = value
  end

  def noncompliant= value = nil
    raise ArgumentError.new "#{__method__}: Must be true or false" unless value == true or value == false or value.nil?
    @noncompliant = value
  end

  def updatetest= value = nil
    raise ArgumentError.new "#{__method__}: Must be true or false" unless value == true or value == false or value.nil?
    @updatetest = value
  end

  def vpnserver= value = nil
    raise ArgumentError.new "#{__method__}: Must be true or false" unless value == true or value == false or value.nil?
    @vpnserver = value
  end

  def yum_internal= value = nil
    raise ArgumentError.new "#{__method__}: Must be true or false" unless value == true or value == false or value.nil?
    @yum_internal = value
  end

  def time= value = false
    # Normally of form "HH:MM_Time_Zone_Label"

    @time = value
  end

  def hasvpnserver= value = nil
    raise ArgumentError.new "#{__method__}: Must be true or false" unless value == true or value == false or value.nil?
    @hasvpnserver = value
  end

  def staff= value = nil
    raise ArgumentError.new "#{__method__}: Must be true or false" unless value == true or value == false or value.nil?
    @staff = value
  end

  def nas= value = nil
    raise ArgumentError.new "#{__method__}: Must be true or false" unless value == true or value == false or value.nil?
    @nas = value
  end

  def ii_vm?
    # True if system is an II VM.

    return @vmhost == '_ii'
  end

  def phys?
    # True if system is a physical machine.

    return @vmhost == '_phys'
  end

  def vm?
    # True if system is a virtual machine, whether II or not.

    return @vmhost != '_phys'
  end

  def non_ii_vm?
    # True if system is a regular (non-II) VM. II VMs and physical machines
    # return false.

    return (@vmhost != '_phys' and @vmhost != '_ii')
  end

  def self.new_from_yaml name, data
    # Initialize a System from YAML data, given the name and the data hash.

    h = {}
    data.each do |k, v|
      h[k.to_sym] = v
    end
    h[:name] = name
    return self.new h
  end

  def to_h
    # Returns a hash containing this object's attributes and their
    # values. Mostly for writing System objects to a file.

    h = {}
    [:name, :day, :vmhost, :is_vmhost, :group, :distro, :skip, :i386,
     :jumphost, :lvs, :noncompliant, :updatetest, :vpnserver, :yum_internal,
     :time, :hasvpnserver, :staff, :nas].each do |attr|
      value = instance_variable_get "@#{attr.to_s}"
      h[attr.to_s] = value if value
    end
    return h
  end
end

###############################################################################
# Globals
###############################################################################

# $dnscache[type][name] = [{:rdata => <rdata>, :ttl => <ttl>}, ...]
$dnscache = Hash.new do |h1, type|
  h1[type] = Hash.new do |h2, name|
    h2[name] = []
  end
end
$system = {}
$steps = [
#  :do_test,
  :do_systemdata,
  :do_build_tasklist,
  :do_activity_loop,
  :do_end_pause,
]
$step = -1
$thread = nil
$opt = {}
$tasklist = TaskList.new {}
$sshable = Set.new
$update_day = nil
$interruptflag = false
$selectable_tasks = []
$selected_tasks = Set.new
$task_cursor = nil
$activity_loop_done = false
$activity_mode = nil
$debug_messages = []
$show_all_tasks = false
$refreshing_taskwin = false

###############################################################################
# Global Methods
###############################################################################

def handle_options
  # Read command-line options from ARGV and set $opt accordingly.
  $opt = Hash.new
  parser = OptionParser.new(1) do |p|
    p.program_name = $PROG_NAME
    p.version = $PROG_VERSION
    p.release = $PROG_RELEASE
    p.separator '---'
    p.summary_indent = '  '
    p.summary_width = 18
    p.banner = "Usage: #{$0} [<options>]"
    p.on('-1', '--skip-group1', :NONE, 'Skip group1 systems') { |v| $opt[:skip1] = 1 }
    p.on('-2', '--skip-group2', :NONE, 'Skip group2 systems') { |v| $opt[:skip2] = 1 }
    p.on('-c', '--command', :REQUIRED, 'Send given command(s) (instead of automatically determining what to do)') { |v| $opt[:cmds] = v.split ',' }
    p.on('-d', '--debug', :NONE, 'Debug mode (extra output)') { |v| $opt[:debug] = 1 }
    p.on('-f', '--force-day', :REQUIRED, 'Force update day instead of detecting (int, itb, prod)') { |v| $opt[:day] = v }
    p.on('-h', '--help', :NONE, 'Print this help text') { |v| puts parser; exit 0 }
    p.on('-l', '--label', :REQUIRED, 'Update only systems with given label (or all given labels)') { |v| $opt[:labels] = v.split ',' }
    p.on('-s', '--summary', :NONE, 'Summary mode (print summary of what to do without doing it)') { |v| $opt[:summary] = 1 }
    p.on('-t', '--test', :NONE, 'Test mode (go through process printing what would be done without doing it)') { |v| $opt[:test] = 1 }
    p.on('-u', '--skip-ungrouped', :NONE, 'Skip ungrouped systems') { |v| $opt[:skipu] = 1 }
    p.on('-v', '--version', :NONE, 'Print version number') { |v| puts "#{$PROG_NAME} #{$PROG_VERSION}-#{$PROG_RELEASE}"; exit 0 }
    p.on('-y', '--yes', :NONE, 'Say yes to all inquiries') { |v| $opt[:yes] = 1 }
  end
  begin
    parser.parse!
  rescue OptionParser::InvalidOption
    puts $!.message
    exit
  end
end

def doublequote_escape str
  # Utility routine for escaping a string's backslashes and double quotes
  # before embedding it within double quotes again. Used by do_backend_cmd().
  return nil if str.nil?
  str.gsub! '\\', '\\\\\\'
  str.gsub! '"', '\\"'
  return str
end

def handle_interrupt int
  # Handles Ctrl-C and Ctrl-\.
  $interruptflag = true
end

def init
  # Tasks to do just after starting.

  # Apparently 'require curses' by itself puts the terminal into a weird state
  # where newlines no longer cause carriage returns, which is bad if the '-h'
  # or '-v' command line options are in effect or we otherwise just want to
  # print some text and exit.
  Curses.close_screen

  # Trap Ctrl-C and Ctrl-\.
  %w(INT QUIT).each { |sig| Signal.trap sig, (method :handle_interrupt).to_proc }

  # Read command-line options.
  handle_options

  # What day is it?
  $update_day = update_day

  # Initialize Tmux stuff.
  unless TmuxUtils::installed?
    system "sudo yum -y -q install tmux"
  end
  unless TmuxUtils::running?
    rc = system "tmux start"
    raise RuntimeError.new "Error starting tmux" unless rc
  end
  if TmuxUtils::in_session?
    $tmux_session = Tmux::Session.current
  else
    exit system "tmux new \"#{$0} #{ARGV.join ' '}; read -p 'Press Enter; screen will clear.'\""
  end
  raise RuntimeError.new "No tmux session" unless TmuxUtils::in_session?

  # Initialize Curses stuff.
  $cui = Curses::Ui::new
  $cui.cbreak
  $cui.nonl
  $cui.curs_set 0
  $cui.noecho
  cols = $cui.cols
  rows = $cui.lines
  $taskwin = $cui.new_textviewer :name => 'taskwin',
                                 :width => cols - (2*cols/3),
                                 :height => 0,
                                 :x => 2*cols/3,
                                 :y => 0,
                                 :focusable => true,
                                 :focus_border => :double,
                                 :unfocus_border => :dotted,
                                 :border_fgcol => Curses::COLOR_RED,
                                 :title => 'Current Tasks',
                                 :title_fgcol => Curses::COLOR_WHITE
  $cui.refresh_stack_push $taskwin
  $outwin = $cui.new_textviewer :name => 'outwin',
                                :width => (2*cols/3),
                                :height => rows - (2*rows/3),
                                :x => 0,
                                :y => 2*rows/3,
                                :focusable => true,
                                :focus_border => :double,
                                :unfocus_border => :dotted,
                                :border_fgcol => Curses::COLOR_YELLOW,
                                :title => 'Output'
  $cui.refresh_stack_push $outwin
  $statwin = $cui.new_textviewer :name => 'summwin',
                                 :width => cols/3,
                                 :height => 2*rows/3,
                                 :x => 0,
                                 :y => 0,
                                 :focusable => true,
                                 :focus_border => :double,
                                 :unfocus_border => :dotted,
                                 :border_fgcol => Curses::COLOR_BLUE,
                                 :title => 'Status'
  $cui.refresh_stack_push $statwin
  $infowin = $cui.new_textviewer :name => 'infowin',
                                 :width => cols/3,
                                 :height => 2*rows/3,
                                 :x => cols/3,
                                 :y => 0,
                                 :focus_border => :double,
                                 :unfocus_border => :dotted,
                                 :border_fgcol => Curses::COLOR_GREEN,
                                 :title => 'Info'
  $cui.refresh_stack_push $infowin
  $window_tab_order = [$taskwin, $outwin, $statwin]
  $window_tab_order.each do |w|
    w.blocking = false
    w.keypad true
  end
  $taskwin.setpos 0, 0
  $cp_normal = $cui.new_cp :fg => Curses::COLOR_WHITE,
                           :bg => Curses::COLOR_BLACK
  $cp_white_on_black = $cp_normal
  $cp_black_on_white = $cui.new_cp :fg => Curses::COLOR_BLACK,
                                  :bg => Curses::COLOR_WHITE
  $cp_red_on_black = $cui.new_cp :fg => Curses::COLOR_RED,
                                 :bg => Curses::COLOR_BLACK
  $cp_green_on_black = $cui.new_cp :fg => Curses::COLOR_GREEN,
                                   :bg => Curses::COLOR_BLACK
  $cp_blue_on_black = $cui.new_cp :fg => Curses::COLOR_BLUE,
                                  :bg => Curses::COLOR_BLACK
  $cp_yellow_on_black = $cui.new_cp :fg => Curses::COLOR_YELLOW,
                                    :bg => Curses::COLOR_BLACK
  $cp_cyan_on_black = $cui.new_cp :fg => Curses::COLOR_CYAN,
                                  :bg => Curses::COLOR_BLACK
  $cp_magenta_on_black = $cui.new_cp :fg => Curses::COLOR_MAGENTA,
                                     :bg => Curses::COLOR_BLACK
  $cp_black_on_red = $cui.new_cp :fg => Curses::COLOR_BLACK,
                                 :bg => Curses::COLOR_RED
  $cp_black_on_green = $cui.new_cp :fg => Curses::COLOR_BLACK,
                                   :bg => Curses::COLOR_GREEN
  $cp_black_on_blue = $cui.new_cp :fg => Curses::COLOR_BLACK,
                                  :bg => Curses::COLOR_BLUE
  $cp_black_on_yellow = $cui.new_cp :fg => Curses::COLOR_BLACK,
                                    :bg => Curses::COLOR_YELLOW
  $cp_black_on_cyan = $cui.new_cp :fg => Curses::COLOR_BLACK,
                                  :bg => Curses::COLOR_CYAN
  $cp_black_on_magenta = $cui.new_cp :fg => Curses::COLOR_BLACK,
                                     :bg => Curses::COLOR_MAGENTA
  $cp_white_on_green = $cui.new_cp :fg => Curses::COLOR_WHITE,
                                   :bg => Curses::COLOR_GREEN
  $cp_white_on_red = $cui.new_cp :fg => Curses::COLOR_WHITE,
                                   :bg => Curses::COLOR_RED
  $taskwin.attrset $cp_normal.to_cp | Curses::A_BOLD
  $cui.focus = $taskwin
  change_info_window
  $cui.event_loop_callback = (method :manage_threads).to_proc

  # Register some event handlers.
  $cui.register_event_handler 'Key', (method :handle_key).to_proc
  $cui.register_event_handler 'Mouse', (method :handle_mouse).to_proc
  $cui.register_event_handler 'FocusIn', (method :handle_focus_in).to_proc
  $cui.register_event_handler 'Debug', (method :handle_debug).to_proc
#  $cui.register_event_handler 'Refresh', (method :handle_refresh).to_proc
  $thread = nil
end

def dialog_ask msg, options = { 'y' => '[y]es', 'n' => '[n]o' }
  # Opens a dialog box with two sections: the message, then the allowed
  # responses. If the user presses a key that is not a key in the given options
  # hash, this method ignores it and keeps waiting for a key it can
  # accept. Returns the key pressed.
  focussave = $cui.focus
  msgwrapped = msg.wrap $cui.cols - 12
  msglines = msgwrapped.split "\n"
  msglongest = msglines.max { |a, b| a.size <=> b.size }
  optlongest = options.values.max { |a, b| a.size <=> b.size }
  winheight = msglines.size + options.size + 3
  winwidth = [ msglongest.size, optlongest.size ].max + 1
  $diawin = $cui.new_dialog :name => 'Dialog',
                            :y => ($cui.lines - winheight)/2,
                            :x => ($cui.cols - winwidth)/2,
                            :height => winheight + 2,
                            :width => winwidth + 2,
                            :focusable => true,
                            :border_fgcol => Curses::COLOR_WHITE,
                            :border_bgcol => Curses::COLOR_RED,
                            :cp => $cp_normal,
                            :msg => msgwrapped,
                            :options => options
  $cui.refresh_stack.push $diawin
  $cui.focus = $diawin
  $cui.capture_keyboard
  $cui.wait
  $diawin.noutrefresh
  $cui.refresh
  $diawin.blocking = true
  $diawin.keypad true
  ch = nil
  loop do
    ch = $cui.focus.getch
    $diawin.noutrefresh
    $cui.refresh
    break if options.keys.include? ch
  end
  $cui.release_keyboard
  $cui.refresh_stack_pop
  $cui.focus = focussave
  $diawin.close
  $diawin = nil
  $cui.refresh
  return ch
end

def dialog_ask_2 msg, options = { 'y' => '[y]es', 'n' => '[n]o' }
  # Opens a dialog box with two sections: the message, then the allowed
  # responses. If the user presses a key that is not a key in the given options
  # hash, this method ignores it and keeps waiting for a button press or a key
  # it can accept. Returns the key related to the button pressed.

  focussave = $cui.focus
  msgwrapped = msg.wrap $cui.cols - 12
  msglines = msgwrapped.split "\n"
  msglongest = msglines.max { |a, b| a.size <=> b.size }
  optlongest = options.values.max { |a, b| a.size <=> b.size }
  winheight = msglines.size + options.size + 3
  winwidth = [ msglongest.size, optlongest.size ].max + 1
  $diawin = $cui.new_dialog :name => 'Dialog',
                            :y => ($cui.lines - winheight)/2,
                            :x => ($cui.cols - winwidth)/2,
                            :height => winheight + 2,
                            :width => winwidth + 2,
                            :focusable => true,
                            :border_fgcol => Curses::COLOR_WHITE,
                            :border_bgcol => Curses::COLOR_RED,
                            :cp => $cp_normal,
                            :msg => msgwrapped,
                            :options => options
  $cui.refresh_stack_push $diawin
  $cui.focus = $diawin
  $cui.capture_keyboard
  $diawin.noutrefresh
  $cui.refresh
  $diawin.blocking = true
  $diawin.keypad true
  ch = nil
  loop do
    ch = $cui.focus.getch
    break if options.keys.include? ch
  end
  $cui.release_keyboard
  $cui.refresh_stack_pop
  $cui.focus = focussave
  $diawin.close
  $diawin = nil
  $cui.refresh
  return ch
end

def outputs str
  # Prints a message to $outwin.

  $outwin.addstr ("#{str}\n".wrap $outwin.pad.width) + "\n"
  $outwin.pad_y = $outwin.pad_height
  $outwin.noutrefresh
  $cui.refresh
end

def debug_outputs str
  # Prints a message with a debug prefix to $outwin, but only if $opt[:debug]
  # is set.

  return unless $opt.key? :debug
  outputs "DEBUG: #{str}"
end

def debug_push str
  # Adds a string to the list of debug messages to be printed at the end.

  $debug_messages.push str
end

def change_info_window
  # Set the text in $infowin based on $cui.focus.
  $infowin.clear
  $infowin.puts "Help"
  $infowin.puts "===="
  $infowin.puts "Tab: Switch windows"
  $infowin.puts "e, x: Save progress and exit"
  $infowin.puts "q: Exit immediately"
  if $cui.focus == $taskwin
    $infowin.puts
    $infowin.puts "\u2191 \u2193: Move task cursor"
    $infowin.puts "\u2190 \u2192: Scroll window"
    $infowin.puts "PgUp, PgDown: Move task cursor one page"
    $infowin.puts "Home: Move task cursor to top"
    $infowin.puts "End: Move task cursor to bottom"
    $infowin.puts "Space, Enter: Toggle highlighted task"
    $infowin.puts "Backspace, -: Deselect highlighted task"
    $infowin.puts "+: Select highlighted task"
    $infowin.puts "t: Select tasks of same type as highlighted one"
    $infowin.puts "a: Select all"
    $infowin.puts "0: Select none"
    $infowin.puts "r: Refresh task list"
    $infowin.puts "G: Perform selected tasks"
    $infowin.puts "m: Mark selected tasks manually complete"
    $infowin.puts "s: Toggle 'show all tasks' (for debugging)"
    $infowin.puts "M: Mark highlighted task 'started'"
    $infowin.puts "?: Check for cyclic dependencies"
    $infowin.puts "d: Print dependencies of highlighted task"
    $infowin.puts "o: Output detailed info about highlighted task"
  elsif $cui.focus == $outwin
    $infowin.puts
    $infowin.puts "\u2190 \u2191 \u2192 \u2193: Scroll window"
    $infowin.puts "PgUp, PgDown: Scroll window farther"
    $infowin.puts "Home: Scroll window to top left"
    $infowin.puts "End: Scroll window to bottom"
  elsif $cui.focus == $statwin
    $infowin.puts
    $infowin.puts "\u2190 \u2191 \u2192 \u2193: Scroll window"
    $infowin.puts "PgUp, PgDown: Scroll window farther"
    $infowin.puts "Home: Scroll window to top left"
    $infowin.puts "End: Scroll window to bottom"
  else
    $infowin.puts
    $infowin.puts "\u2190 \u2191 \u2192 \u2193: Scroll window"
    $infowin.puts "PgUp, PgDown: Scroll window farther"
    $infowin.puts "Home: Scroll window to top left"
    $infowin.puts "End: Scroll window to bottom"
  end
  $infowin.noutrefresh
end

def expire_dns_cache
  # Go through $dnscache and delete any expired records. Do some other checks
  # as well.
  #
  # Structures of $dnscache: $dnscache[type], where type is the DNS record type
  # string('A', 'AAAA', 'CNAME', etc.), is a hash indexed by DNS record
  # name. $dnscache[type][name] is either a hash with keys :not_found and
  # :expires, or an array containing hashes of DNS data (keys :rdata,
  # :expires).

  now = Time.now.to_f

  # First we're going to clean any expired :not_found records.
  $dnscache.each do |type, name_h|
    name_h.delete_if do |name, data_o|
      data_o.kind_of? Hash and data_o[:expires].to_f <= now
    end
  end

  # Next we'll go through any name_h arrays and get rid of records that have
  # expired.
  $dnscache.each do |type, name_h|
    name_h.each do |name, data_a|
      next unless data_a.kind_of? Array
      data_a.delete_if { |data_h| data_h[:expires].to_f <= now }
    end
  end

  # Delete any name entries that have no name records.
  $dnscache.each do |type, name_h|
    name_h.delete_if do |name, data_o|
      data_o.respond_to? :size and data_o.size == 0
    end
  end

  # Delete any empty type entries. If there are no entries of that type, don't
  # keep the key around.
  $dnscache.delete_if { |type, name_h| name_h.keys.size == 0 }
end

def read_dns_cache
  # Reads $dnscachefile and puts any unexpired records into $dnscache.
  return nil unless File.exist? $dnscachefile
  $dnscache = YAML.load (File.read $dnscachefile)
  if $dnscache.nil?
    $debug_messages.push "Unable to open DNS cache file #{$dnscachefile}: #{$!}"
    fin
    exit 1
  end
  expire_dns_cache
end

def dns_cached_lookup name, type
  # Look for a record with the given type and name in $dnscache. If there's
  # nothing matching those parameters in $dnscache, look for the same in DNS
  # and cache the result. In either case, return the result as an array of text
  # results, or an empty array if nothing was found at all.

  # Expire any records that may have expired in $dnscache since the last
  # lookup.
  expire_dns_cache
  now = Time.now.to_f
  results = []
  # There may be a record in the $dnscache -- either a hash with a :not_found
  # key and an :expires timestamp, or an array of results. Or there may be
  # nothing at all, meaning there's no cached result whatsoever for the given
  # name and type.
  if ($dnscache.key? type) \
    and ($dnscache[type].respond_to? :key?) and ($dnscache[type].key? name)
    # There's something here, but whether it's a not-found or a real result
    # remains to be seen. Let's look at that.
    if $dnscache[type][name].respond_to? :key? \
       and $dnscache[type][name].key? :not_found
      # It's in the cache as not found. Return an empty result.
      return []
    elsif $dnscache[type][name].kind_of? Array and $dnscache[type][name].size > 0
      # It's in the cache. Return the rdata items.
      return $dnscache[type][name].map { |data_h| data_h[:rdata] }
    end
  end
  # Apparently the query wasn't found in the cache, so contact DNS for the data
  # (and put it in the cache).
  res = Net::DNS::Resolver.new
  packet = res.search name, (Object.const_get "Net::DNS::#{type}")
  return nil unless packet      # This would be a DNS lookup failure.
  answer = packet.answer
  if answer.size > 0
    # The query retrieved at least one resource record. Put the results in the
    # cache and return the rdata items to the caller.
    answer.each do |rr|
      ttl = rr.ttl
      rdata = rr.value
      expires = now + ttl.to_f
      unless ($dnscache.key? type) and ($dnscache[type].kind_of? Hash)
        $dnscache[type] = Hash.new
      end
      unless ($dnscache[type].key? name) and ($dnscache[type][name].kind_of? Array)
        $dnscache[type][name] = Array.new
      end
      $dnscache[type][name].push({ :rdata => rdata,
                                   :expires => expires })
      results.push rdata
    end
  else
    # The query found no results. Put that in the cache too, using $ttl_undef
    # from the settings.
    unless ($dnscache.key? type) and ($dnscache[type].kind_of? Hash)
      $dnscache[type] = Hash.new
    end
    unless ($dnscache[type].key? name) and ($dnscache[type][name].kind_of? Hash)
      $dnscache[type][name] = {}
    end
    $dnscache[type][name] = { :not_found => true,
                              :expires => now + $ttl_undef.to_f }
  end
  return results
end

def dns_exists domain
  # Given a domain name, returns true if it exists in DNS and false if
  # not. "Exists" means that an AAAA, A, or CNAME record exists for it --
  # basically, if DNS would come back with an IP address, it "exists."

  rdata = dns_cached_lookup domain, 'AAAA'
  return true if rdata and rdata.size > 0
  rdata = dns_cached_lookup domain, 'A'
  return true if rdata and rdata.size > 0
  rdata = dns_cached_lookup domain, 'CNAME'
  return true if rdata and rdata.size > 0
  return false
end

def ensure_dns_domains system
  # Make sure each domain given as keys in the argument hash exists in DNS,
  # basically just calling dns_exists for each one. If it doesn't exist, just
  # print a message; the sysadmin running the script can decide what to do
  # about it, if anything.

  anyout = false
  system.keys.each do |sys|
    unless dns_exists sys
      # Not doing anything about systems that aren't in DNS; they might have been
      # deleted, or they might be new ones that don't exist yet, or a lot of
      # things might be the case that this script can't divine.
      anyout = true
      $outwin.puts "System '#{sys}' in systemfile but not found in DNS; just warning ya"
    end
  end
  if anyout
    $outwin.noutrefresh
    $cui.refresh
  end
end

def write_dns_cache
  # Writes $dnscache to $dnscachefile.

  FileUtils.mkdir_p (File.dirname $dnscachefile)
  # No point saving expired records.
  expire_dns_cache
  File.write $dnscachefile, (YAML.dump $dnscache)
end

def get_ldap_systems
  # Get all systems defined in LDAP. These come originally from the /etc/hosts
  # file on ds1, the main directory server, and that is the authoritative list
  # of systems we consider "ours." Returns nil if there was an error. If not,
  # returns a Hash whose keys are the systems' main hostnames and whose values
  # are Hashes with keys :addresses (IP addresses) and :aliases (any other
  # hostnames). All hostnames returned are shortened hostnames.
  systems = Hash.new
  ldap = Net::LDAP.new :host => $ldaphosts[0],
                       :port => 389,
                       :auth => {
                         :method => :anonymous,
                       }
  begin
    ldap.bind
  rescue Net::LDAP::Error => err
    $debug_messages.push "Unable to connect to LDAP server #{$ldaphosts[0]}:389: #{err}"
    fin
    exit 1
  end

  treebase = "ou=Hosts,dc=goc"
  filter = Net::LDAP::Filter.eq("objectClass", "ipHost")
  attrs = %w(cn ipHostNumber)
  results = ldap.search :base => treebase,
                        :filter => filter,
                        :attributes => attrs
  if results.nil?
    $debug_messages.push "LDAP search returned error: #{ldap.get_operation_result}"
    fin
    exit 1
  end
  results.each do |entry|
    hostnames = entry['cn'].map { |h| (h.split '.').first }
    main_hostname = hostnames.shift
    # Sometimes there are placeholders for entries that have been undefined.
    next if main_hostname.start_with? 'unused-'
    if main_hostname.empty?
      $debug_messages.push "Null LDAP host entry ... hostnames = #{hostnames.join ', '} ... ignoring"
      next
    end
    addresses = entry['ipHostNumber']
    systems[main_hostname] =
      {
        :addresses => addresses,
        :aliases => hostnames
      }
  end
  return systems
end

def scan_vmhost vmhost
  # Uses SSH and lsvm to get a list of VMs from the given VM host. Returns an
  # Array. Technically, it only returns the VMs on the host that are either up
  # right now or marked as autostart; if they're down and marked not to
  # autostart, they are ignored. This takes a couple of seconds, so this is a
  # good method to thread if you're doing that.

  lines = `ssh -x #{vmhost} "/opt/sbin/lsvm -na"`.split "\n"
  anyout = false
  if $?.exitstatus != 0
    anyout = true
    $outwin.puts "ERROR: Unable to scan host '#{vmhost}'"
    return []
  end
  vms = []
  lines.each do |line|
    (vm, state, auto) = line.split(/\s+/, 4)
    # If a VM is auto and down, or noauto and up, I should know about it
    if auto == 'auto' and state == 'down'
      anyout = true
      $outwin.puts "VM '#{vm}' on host '#{vmhost}' is set autostart, but is down"
    end
    if auto == 'noauto' and state == 'up'
      anyout = true
      $outwin.puts "VM '#{vm}' on host '#{vmhost}' is up but not set autostart"
    end
    if auto == 'auto' or state == 'up'
      short = (vm.split '.', 2).first
      if dns_exists short
        vms.push vm
      else
        anyout = true
        $outwin.puts "VM '#{vm}' on host '#{vmhost}' does not exist in DNS; not setting vmloc to '#{vmhost}'"
      end
    end
  end
  if anyout
    $outwin.noutrefresh
    $cui.refresh
  end
  return vms
end

def read_systemdata
  # Read system data from $systemdatafile into $system. Called by
  # refresh_systemdata.

  return nil unless File.exist? $systemdatafile

  yamldata = YAML.load (File.read $systemdatafile)
  if yamldata.nil?
    $debug_messages.push "Unable to read #{$systemdatafile}: #{$!}"
    fin
    exit 1
  end

  yamldata.each do |sys, data|
    $system[sys] = System.new_from_yaml sys, data
  end
end

def refresh_systemdata
  # Reads $systemdatafile (using read_systemdata, q.v.) into $system, then
  # queries LDAP. Adds to $system any systems found in LDAP that weren't in
  # that Hash already, and queries systems labeled 'is_vmhost' for their VMs
  # (see scan_vmhost), adding 'vmhost' values to those VMs based on what host
  # they're on.

  outputs ">>> READING SYSTEM DATA ..."
  anyout = false
  read_systemdata
  ensure_dns_domains $system
  # This is where new systems get added to $system. There won't be much data
  # about them yet.
  ldapdata = get_ldap_systems
  if ldapdata and ldapdata.size > 0
    ldapdata.keys.each do |sys|
      unless dns_exists sys
        anyout = true
        $outwin.puts "System '#{sys}' in LDAP but not found in DNS; just warning ya"
      end
      # It's possible for there to be systems in $system that aren't under
      # their main LDAP hostname but rather under an alias; as long as the
      # hostname gets you to them via SSH, that's all I care about, but here we
      # must not add a new entry for a system that's in there already.
      # Therefore if a system is found under an alias, let LDAP be the
      # authority and rename it in $system.
      unless $system.key? sys
        ldapdata[sys]['aliases'] = [] unless ldapdata[sys].key? 'aliases'
        ldapdata[sys]['aliases'].each do |thealias|
          if $system.key? thealias
            anyout = true
            $outwin.puts "System '#{thealias}' in systemfile is an alias of '#{sys}' in LDAP; renaming"
            $system[sys] = $system.delete thealias
            break
          end
        end
      end
      # If there isn't already a record in $system for system, make an empty
      # one.
      unless $system.key? sys
        # Systems that are in internal DNS but not public DNS shouldn't be in the
        # systemlist. They're VPN hosts or test VMs that don't have a public IP
        # and may not have a public network connection. They don't get OS
        # updates.
        if dns_exists "#{sys}.grid.iu.edu" or dns_exists "#{sys}.uits.indiana.edu"
          $system[sys] = System.new({ :name => sys })
        else
          anyout = true
          outputs "System '#{sys}' exists internally but not externally -- not adding"
        end
      end
    end
  end
  # Look at the VMs on each VM host, setting 'vmhost' to the VM host on each VM
  # found.
  threads = {}
  $system.each do |sys, data|
    if data.is_vmhost and !data.skip
      threads[sys] = Thread.new { scan_vmhost sys }
    end
  end
  threads.each do |sys, thread|
    vms = thread.value
    vms.each do |vm|
      short = vm.sub(/\.\d*$/, '')
      $system[short].vmhost = sys
    end
  end

  # Now generate a $vms_on_vmhost hash of arrays, telling us what VMs are on
  # which VM hosts.
  $vms_on_vmhost = {}
  $system.each do |sys, data|
    next if data.phys? or data.ii_vm?
    vmhost = data.vmhost
    $vms_on_vmhost[vmhost] = [] unless $vms_on_vmhost.key? vmhost
    $vms_on_vmhost[vmhost].push sys
  end

  # Refresh the output window if there was any output.
  if anyout
    $outwin.noutrefresh
    $cui.refresh
  end
  return true
end

def check_systemdata
  # Check $system to make sure nothing weird is in there. Returns true if
  # everything is OK and false (after printing the error) if there is a
  # problem.

  error = false
  $system.each do |sys, data|
    next if data.skip or data.noncompliant
    unless data.vmhost
      debug_push "#{sys}: No 'vmhost' attribute"
      error = true
    end
    if data.is_vmhost and !(%w(kvm vmw).include? data.is_vmhost)
      debug_push "#{sys}: 'is_vmhost' is neither 'kvm' nor 'vmw' (it is '#{data.is_vmhost}')"
      error = true
    end
    if data.is_vmhost and !data.phys?
      debug_push "#{sys}: Marked 'is_vmhost' but not '_phys'"
      error = true
    end
  end
  return !error
end

def write_systemdata
  # Write $system back out.
  systemdata = {}
  $system.keys.sort.each do |k|
    h = $system[k].to_h.reject { |k, v| k == 'name' or k == 'hasvpnserver' or v.nil? }
    systemdata[k] = h
  end
  File.write $systemdatafile, (YAML.dump systemdata)
end

def read_tasklist
  # Read $tasklist from $savefile.
  $tasklist = YAML.load(File.read $savefile)
end

def maybe_read_tasklist
  # Load $tasklist from $savefile, if it exists and the user chooses
  # to. Returns true if successful, false if it doesn't exist or the user
  # chooses not to load it, nil if some other error.

  return false unless File.exist? $savefile
  stat = File.stat $savefile
  unless stat
    debug_push "Save file #{$savefile} exists, but unable to stat it: #{$!}"
    return nil
  end
  response = dialog_ask "A save file exists, written at #{(File.stat $savefile).mtime.localtime.strftime '%F %T'}. Use file?",
                        { 'y' => 'load tasks from file', 'n' => 'delete it and generate new tasks)' }
  if response == 'y'
    read_tasklist
    # Could delete $savefile here, but not going to; if there's an error, I
    # want to be able to fix it and retry.
  else
    unlink $savefile
    return false
  end
  return true
end

def update_day
  # Find out whether today is an update day or not, and if so, which one.
  # Returns nil if it's not an update day, 'int' if it's "jump2 day" (the
  # Monday before the third Tuesday of the month), 'itb' if it's "ITB day" (the
  # third Tuesday of the month), or 'prod' if it's "production day" (the fourth
  # Tuesday of the month).

  if $opt.key? :day
    return $opt[:day] if %w(int itb prod).include? $opt[:day]
    return nil
  end
  today = Time.now.to_date
  first_of_month = Date.new today.year, today.month, 1
  last_of_month = first_of_month.next_month.prev_day
  tuesdays_this_month = (first_of_month..last_of_month).to_a.select { |d| d.tuesday? }
  itb_day = tuesdays_this_month[2]
  jump2_day = itb_day.prev_day
  prod_day = tuesdays_this_month[3]
  return 'int' if today == jump2_day
  return 'itb' if today == itb_day
  return 'prod' if today == prod_day
  return nil
end

def check_tasks
  # Go through $tasklist and look for trouble. Types of trouble:
  #
  # * Circular dependencies.  X depends on Y which depends on X, and the like.
  # * Too many failed attempts (not implemented).
  outputs ">>> CHECKING TASKLIST ..."
  if $tasklist.find_cycles
    debug_push $tasklist.status
    return false
  end
  return true
end

def build_task_list
  # Build the global $tasklist object based on $system.

  outputs ">>> BUILDING TASKLIST ..."
  # Unless the user has used the -c option on the command line to give this
  # script specific commands to run, we'll be using $update_day to figure out
  # what to do.
  unless $opt.key? :cmds
    return true if $update_day.nil? or $update_day.empty? or $update_day == 'none'
  end
  systems = []
  systemgroups = []

  def add_reposync_tasks systems
    # Add reposync tasks to $tasklist.
    reposync_tasks = systems.select do |sys|
      $system[sys].yum_internal
    end.map do |sys|
      Task.new :id => "#{sys}/reposync",
               :type => :reposync,
               :system => sys,
               :cmd => '/root/repoupdate.sh',
               :cmdsudo => true,
               :timereq => $tasktime[:reposync],
               :waitforothers => true,
               :ask => true
    end
    $tasklist.add reposync_tasks
    return reposync_tasks
  end

  def add_reposync_done_task
    # Add a reposync_done checkpoint task if there are any reposync tasks.
    return unless $tasklist.select { |t| t.type == :reposync }.size > 0
    task = Task.new :id => 'reposyncdone',
                    :type => :reposyncdone,
                    :system => '(reposyncdone)',
                    :cmd => '&checkpoint',
                    :param => 'Reposyncs done',
                    :timereq => 0,
                    :ask => false
    $tasklist.add task
    return task
  end

  def add_timewait_tasks systems
    # Add timewait tasks to $tasklist.
    timewaittask = {}
    systems.each do |sys|
      next unless $system[sys].time
      timelabel = "time_#{$system[sys].time}"
      next if timewaittask.key? timelabel
      timewaittask[timelabel] = Task.new :id => finallabel,
                                         :type => :time,
                                         :system => '(timed)',
                                         :cmd => '&timewait',
                                         :param => $system[sys].time,
                                         :timereq => 0,
                                         :ask => false

      # If 'sys' is a VM (and isn't an II VM, and isn't the updatetest VM),
      # make sure the VM host also has 'finallabel', and every other VM on that
      # host as well. We will be exempting these systems from the checkpoint
      # framework, and if we have a VM being exempted without its host, or
      # other VMs on that host, we'll end up updating and shutting down the VM
      # host before we shut down 'sys', or we'll update and shut down 'sys' and
      # be waiting for it to come back up before ever updating the VM
      # host. They have to go together. This is why timed updates suck.

      # Find vmhost
      vmhost = ''
      if !$system[sys].ii_vm? and !$system[sys].updatetest
        vmhost = $system[sys].vmhost

        # Find other VMs on vmhost
        othervms = $system.select { |h, d| d.vmhost == vmhost }.keys

        # For vmhost and othervms, if they don't already have 'time', give
        # them 'finaltime'.
        othervms.each do |othervm|
          $system[othervm].time = $system[sys].time
        end
      end
    end
    $tasklist.add timewaittask.values
    return timewaittask
  end

  def get_systemgroups systems
    # Look for system groups among the labels of 'systems'. Returns a list of system
    # group labels. Note that this doesn't actually group the systems by label.
    found_systemgroup = Set.new
    systems.each do |sys|
      next unless $system[sys].group
      found_systemgroup.add $system[sys].group
    end
    return found_systemgroup.to_a.sort
  end

  def add_lvs_switch_tasks lvsservers, systemgroups
    # Add LVS-switching tasks for the given lvsservers and systemgroups to
    # $tasklist and return them. If there aren't any system groups, don't
    # bother and return an empty hash.

    return {} unless systemgroups.size > 0
    task = {}

    # There will need to be tasks to switch LVS back to normal after updates
    # are done.
    lvsservers.each do |lvs|
      task["#{lvs}_normal"] =
        Task.new(:id => "#{lvs}/LVS_normal",
                 :type => :LVS,
                 :system => lvs,
                 :cmd => '/usr/local/lvs/bin/goc_lvs.pl',
                 :param => 'normal',
                 :cmdsudo => true,
                 :deps => Set.new(lvsservers.map { |s| "#{s}/LVS_#{systemgroups.last}" }),
                 :timereq => $tasktime[:LVS],
                 :ask => true)
    end

    # Create tasks for each system group now.
    systemgroups.each do |sysgrp|
      # Make tasks to switch each LVS server so as to update the given group.
      lvsservers.each do |lvs|
        task["#{lvs}_#{sysgrp}"] =
          Task.new(:id => "#{lvs}/LVS_#{sysgrp}",
                   :type => :LVS,
                   :system => lvs,
                   :cmd => "/usr/local/lvs/bin/goc_lvs.pl -u #{sysgrp}",
                   :param => sysgrp,
                   :cmdsudo => true,
                   :timereq => $tasktime[:LVS],
                   :ask => true)
      end
    end

    # Also, in each case, lvs1's task depends on lvs2's, since it's best to
    # change lvs2 before lvs1 (this prepares lvs2 to momentarily assume master
    # status with the new parameters as lvs1's keepalived restarts). We're kind
    # of assuming here that the first LVS server in lexical sort order will be
    # the default master, but that's how it is.
    (['normal'] + systemgroups).each do |sysgrp|
      prev_lvs = nil
      lvsservers.sort.each do |lvs|
        unless prev_lvs.nil?
          task["#{prev_lvs}_#{sysgrp}"].depends_on task["#{lvs}_#{sysgrp}"]
        end
        prev_lvs = lvs
      end
    end

    $tasklist.add task.values
    return task
  end

  def add_group_done_tasks systemgroups
    # Add the group_done tasks to $tasklist and return them. If there aren't
    # any system groups, don't bother and return an empty hash.

    return {} unless systemgroups.size > 0

    # Create tasks for each system group now.
    task = (['ungrouped'] + systemgroups).map do |sysgrp|
      [ sysgrp, (Task.new :id => "#{sysgrp}/groupdone",
                          :type => :groupdone,
                          :system => "(#{sysgrp})",
                          :cmd => '&checkpoint',
                          :param => "#{sysgrp} osupdate tasks finished",
                          :timereq => 0,
                          :ask => false) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  def add_preupdate_tasks systemgroups
    # Add preupdate checkpoint tasks for each system group to the tasklist and
    # return them. If there aren't any system groups, still create one for
    # 'ungrouped'.

    # Create tasks for each system group now.
    task = (['ungrouped'] + systemgroups).map do |sysgrp|
      [ sysgrp, (Task.new :id => "#{sysgrp}/preupdate",
                          :type => :preupdate,
                          :system => "(#{sysgrp})",
                          :cmd => '&checkpoint',
                          :param => "#{sysgrp} ready for update",
                          :timereq => 0,
                          :ask => false) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  def add_postupdate_tasks systemgroups
    # Add postupdate checkpoint tasks for each system group to the tasklist and
    # return them. If there aren't any system groups, still create one for
    # 'ungrouped'.

    # Create tasks for each system group now.
    task = (['ungrouped'] + systemgroups).map do |sysgrp|
      [ sysgrp, (Task.new :id => "#{sysgrp}/postupdate",
                          :type => :postupdate,
                          :system => "(#{sysgrp})",
                          :cmd => '&checkpoint',
                          :param => "#{sysgrp} done with update task",
                          :timereq => 0,
                          :ask => false) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  def add_group_vm_shutdown_ready_tasks systemgroups
    # Add shutdown-ready checkpoint tasks for each system group to the tasklist
    # and return them. If there aren't any system groups, still create one for
    # 'ungrouped'.

    # Create tasks for each system group now.
    task = (['ungrouped'] + systemgroups).map do |sysgrp|
      [ sysgrp, (Task.new :id => "#{sysgrp}/group_vm_shutdown_ready",
                          :type => :group_vm_shutdown_ready,
                          :system => "(#{sysgrp})",
                          :cmd => '&checkpoint',
                          :param => "VMs of group '#{sysgrp}' ready for shutdown",
                          :timereq => 0,
                          :ask => false) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  def add_group_shutdown_ready_tasks systemgroups
    # Add shutdown-ready checkpoint tasks for each system group to the tasklist
    # and return them. If there aren't any system groups, still create one for
    # 'ungrouped'.

    # Create tasks for each system group now.
    task = (['ungrouped'] + systemgroups).map do |sysgrp|
      [ sysgrp, (Task.new :id => "#{sysgrp}/group_shutdown_ready",
                          :type => :group_shutdown_ready,
                          :system => "(#{sysgrp})",
                          :cmd => '&checkpoint',
                          :param => "Physical servers of group '#{sysgrp}' ready for shutdown",
                          :timereq => 0,
                          :ask => false) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  def add_osupdate_tasks systems
    # Adds osupdate tasks for all systems that will be updated in this run. Make
    # the list of systems to affect.

    task = systems.map do |sys|
      [ sys, (Task.new :id => "#{sys}/osupdate",
                       :type => :osupdate,
                       :system => sys,
                       :cmd => '/opt/sbin/osupdate',
                       :cmdsudo => true,
                       :timereq => $tasktime[:osupdate],
                       :ask => true) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  def add_grub_pause_tasks systems
    # For each system labeled 'i386', make a grub_pause task.

    task = systems.select do |sys|
      $system[sys].i386
    end.map do |sys|
      [ sys, (Task.new :id => "#{sys}/grub_pause",
                       :type => :grub_pause,
                       :system => sys,
                       :cmd => '&grub_pause',
                       :timereq => $tasktime[:grub_pause],
                       :ask => false) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  def add_system_shutdown_ready_tasks systems
    # For each system in the given array, make a system_shutdown_ready checkpoint
    # task that signifies that all tasks are done for that system (other than a
    # reboot or shutdown). This means the system is ready for its shutdown task.

    task = systems.map do |sys|
      [ sys, (Task.new :id => "#{sys}/system_shutdown_ready",
                       :type => :system_shutdown_ready,
                       :system => sys,
                       :cmd => '&checkpoint',
                       :param => "System #{sys} ready for shutdown",
                       :timereq => 0,
                       :ask => false) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  def add_shutdown_tasks systems
    # For each system in the given array, make a shutdown task. Note that we
    # don't set 'cmd' here; what command to run varies with the system. That will
    # have to be set later.

    task = systems.map do |sys|
      [ sys, (Task.new :id => "#{sys}/shutdown",
                       :type => :shutdown,
                       :system => sys,
                       :cmd => '(shutdown)',
                       :cmdsudo => true,
                       :timereq => $tasktime[:shutdown],
                       :ask => true) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  def add_shutdown_delay_tasks systems
    # For each system in the given array, make a shutdown delay task.

    task = systems.map do |sys|
      [ sys, (Task.new :id => "#{sys}/shutdown_delay",
                       :type => :shutdown_delay,
                       :system => sys,
                       :cmd => '&delay',
                       :param => 120,
                       :timereq => 120,
                       :ask => false) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  def add_ssh_test_tasks systems
    # For each system in the given array, make an ssh_test task.

    task = systems.map do |sys|
      [ sys, (Task.new :id => "#{sys}/ssh_test",
                       :type => :ssh_test,
                       :system => sys,
                       :cmd => '&ssh_test',
                       :timereq => $tasktime[:ssh_test],
                       :ask => false) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  def add_complete_tasks systems
    # For each system in the given array, make a complete task that signifies
    # that all tasks are done for that system, *including* the shutdown task and
    # the ssh check after it comes back up.

    task = systems.map do |sys|
      [ sys, (Task.new :id => "#{sys}/complete",
                       :type => :complete,
                       :system => sys,
                       :cmd => '&complete',
                       :timereq => $tasktime[:complete],
                       :ask => false) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  def get_group_systems systems, group
    # For a given system group (or 'ungrouped'), return a reference to a list of
    # systems in that group. Since VM systems are labeled with their group and the
    # VMs on it are not, we'll have to differentiate between VMs and non-VMs.

    groupsystems = []
    systems.each do |sys|
      # Physical servers are labeled with their group, if they're in one. With
      # II VMs, since we don't update their hosts, we don't have records for
      # their hosts, so their groups will have to be determined by their own
      # labels.
      if $system[sys].phys? or $system[sys].ii_vm?
        if group == 'ungrouped'
          groupsystems.push sys unless $system[sys].group
        else
          groupsystems.push sys if $system[sys].group == group
        end
      else
        # It's a non-II VM.  Find out what group its VM host is in, if any.
        vmhost = $system[sys].vmhost
        if systems.include? vmhost
          if group == 'ungrouped'
            groupsystems.push sys unless $system[vmhost].group
          else
            groupsystems.push sys if $system[vmhost].group == group
          end
        else
          # If 'vmhost' isn't being updated today, 'sys' isn't considered to
          # be in its group.
          groupsystems.push sys if group == 'ungrouped'
        end
      end
    end
    return groupsystems
  end

  def add_all_vms_down_tasks systems
    # Adds allvmsdown tasks for the VM hosts among the given systems.

    task = systems.select do |sys|
      $system[sys].is_vmhost and $vms_on_vmhost.key? sys and $vms_on_vmhost[sys].size > 0
    end.map do |sys|
      [ sys, (Task.new :id => "#{sys}/allvmsdown",
                       :type => :allvmsdown,
                       :system => sys,
                       :cmd => '&allvmsdown',
                       :timereq => $tasktime[:allvmsdown],
                       :ask => true) ]
    end.to_h
    $tasklist.add task.values
    return task
  end

  # Step 1: What systems to affect? If -c, assume all systems. Otherwise, use
  # $update_day to determine which ones.
  if $opt.key? :cmds
    systems = $system.keys
  else
    # What systems are updated today, according to their 'day' key?
    systems = $system.select do |sys, d|
      d.day == $update_day
    end.keys
  end

  # Reject systems with a 'skip' key or the 'noncompliant' label.
  systems.reject! do |sys|
    $system[sys].skip or $system[sys].noncompliant
  end

  # If the -l command-line option was given, reject servers that do not possess
  # all of the labels listed there.
#  if $opt.key? :labels
#    systems.reject! do |sys|
#      missing_labels = false
#      $opt[:labels].each do |label|
#        unless system_key? sys, label
#          missing_labels = true
#          break
#        end
#      end
#      missing_labels
#    end
#  end

  # Now it's time to start making tasks, but there's a branch here: if the -c
  # command appeared on the command line, make command tasks for whatever was
  # there, link them together, and return. Otherwise, do the osupdate process
  # as normal.
  if $opt.key? :cmds
    task = {}
    sequence = 0
    prev_cmdkey = nil
    $opt[:cmds].each do |cmd|
      basecmd = File.basename((cmd.split /\s+/, 2).first)
      cmdkey = "#{basecmd}_#{sequence}"
      checkpoint_label = "#{cmdkey}_done"
      # Make a checkpoint task for when all the system-dependent ones we're
      # about to create to do 'cmd' are done, so we don't move on to the next
      # 'cmd' until all systems have done this 'cmd'.
      task[checkpoint_label] =
        Task.new(:id => "#{cmdkey}/done",
                 :type => checkpoint_label.to_sym,
                 :system => "(#{checkpoint_label})",
                 :cmd => '&checkpoint',
                 :param => "#{cmdkey} done",
                 :timereq => 0,
                 :ask => false)
      $tasklist.add task[checkpoint_label]
      # Make the system-dependent tasks for 'cmd'.
      systems.each do |sys|
        sys_label = "#{sys}_#{cmdkey}"
        task[sys_label] =
          Task.new(:id => "#{sys}/#{cmdkey}",
                   :type => cmdkey.to_sym,
                   :system => sys,
                   :cmd => cmd,
                   :cmdsudo => true,
                   :timereq => 10,
                   :ask => true)
        # Make the task we just created dependent on the checkpoint that
        # occurred after the previous 'cmd'.
        unless prev_cmdkey.nil?
          task[sys_label].depends_on task["#{prev_cmdkey}_done"]
        end
        $tasklist.add task[sys_label]
        # Add the task we just created to the dependencies of the checkpoint
        # task we recently created. That checkpoint won't happen until all
        # tasks related to 'cmd' happen.
        task[checkpoint_label].depends_on task[sys_label]
      end
      prev_cmdkey = cmdkey
      sequence += 1
    end
    # Now create a :complete task for each system and make it dependent on the
    # last checkpoint.
    systems.each do |sys|
      sys_label = "#{sys}_complete"
      task[sys_label] =
        Task.new(:id => "#{sys}/complete",
                 :type => :complete,
                 :system => sys,
                 :cmd => '(complete)',
                 :deps => Set.new(task["#{prev_cmdkey}_done"]),
                 :timereq => $tasktime[:complete],
                 :ask => false)
      $tasklist.add task[sys_label]
    end
    return 1
  end   # Done with the -c option

  # Now it's time to build the tasks for a normal, non '-c' osupdate run ...

  # If it's jump2 day, create the reposync task(s): yum-internal systems must be
  # reposynced, and all osupdate tasks must wait until the reposyncs are done.
  reposynctasks = []
  if $update_day == 'int'
    reposynctasks = add_reposync_tasks systems
  end

  # Create a 'reposyncdone' checkpoint task if there are any
  # reposynctasks. Make it dependent on all tasks in reposynctasks.
  reposyncdonetask = nil
  if reposynctasks.size > 0
    reposyncdonetask = add_reposync_done_task
    begin
      reposyncdonetask.depends_on reposynctasks
    rescue => err
      fin
      exit 1
    end
  end

  # Look for any timewait ('alarm clock') labels and create tasks for
  # them. Store them in a hash so we can refer to them when needed.
  timewaittask = add_timewait_tasks systems

  # Look for any system groups. These will be labeled 'group1', 'group2',
  # etc. and will typically be only production systems.
  systemgroups = get_systemgroups systems

  # Make LVS-switching tasks for each group. This will be empty if there are no
  # systemgroups.
  lvsservers = systems.select { |s| $system[s].lvs }
  lvsswitchtask = add_lvs_switch_tasks lvsservers, systemgroups

  # Make checkpoint tasks signifying that each group's updates are done. This
  # will also be empty if there are no systemgroups.
  groupdonetask = add_group_done_tasks systemgroups

  # Make preupdate checkpoints for each group.
  preupdatetask = add_preupdate_tasks systemgroups
  
  # Make checkpoints for each group indicating that the group's VMs and
  # physical servers are ready for shutdown.
  groupvmshutdownreadytask = add_group_vm_shutdown_ready_tasks systemgroups
  groupshutdownreadytask = add_group_shutdown_ready_tasks systemgroups

  # Make osupdate tasks for each system.
  osupdatetask = add_osupdate_tasks systems

  # Make grub_pause for systems labeled '32bit'.
  grubpausetask = add_grub_pause_tasks systems

  # Make checkpoint tasks signifying that the given system is ready for shutdown.
  systemshutdownreadytask = add_system_shutdown_ready_tasks systems

  # Make shutdowntasks for each system.
  shutdowntask = add_shutdown_tasks systems

  # Make shutdowndelay and ssh test tasks for each system.
  shutdowndelaytask = add_shutdown_delay_tasks systems
  sshtesttask = add_ssh_test_tasks systems

  # Make allvmsdown tasks for VM systems.
  allvmsdowntask = add_all_vms_down_tasks systems

  # Make complete tasks signifying that everything that needs to be done on a
  # given system is done.
  completetask = add_complete_tasks systems

  # Now we're going to make dependencies between all these tasks. First, if
  # there are system groups, make the dependencies among the tasks that affect
  # whole groups. Deal with ungrouped systems first, then group1 systems, then
  # group2 systems, etc.

  # We'll need to remember the previous system group because each group must be
  # complete before we move on to the next group.
  prev_sysgrp = nil

  # Away we go, treating ungrouped systems as members of a pseudogroup called
  # 'ungrouped'.
  (['ungrouped'] + systemgroups).each do |sysgrp|
    # Tell the user to shift LVS for the given group (unless it's 'ungrouped'),
    # do the osupdates for the group, do whatever other stuff depends on
    # osupdates, then do the rpmconfs and the puppets, then the shutdowns and
    # whatever they depend on.

    # But first make a list of the systems to affect.
    groupsystems = get_group_systems systems, sysgrp

    ###########################################################################
    # Group task: LVS switch
    ###########################################################################

    # The LVS switching tasks for 'sysgrp' depends on the previous group's
    # systems all being complete. Later on, when we make those 'complete'
    # tasks, we'll add them to 'prev_sysgrp_completes'.
    if prev_sysgrp and sysgrp != 'ungrouped' and groupdonetask.key? prev_sysgrp
      lvsservers.each do |lvs|
        if lvsswitchtask.key? "#{lvs}_#{sysgrp}"
          lvsswitchtask["#{lvs}_#{sysgrp}"].depends_on groupdonetask[prev_sysgrp]
        end
      end
    end

    ###########################################################################
    # Group task: Preupdate checkpoint task
    ###########################################################################

    # The group's preupdate task depends on each 'lvsswitchtask'.
    lvsservers.each do |lvs|
      preupdatetask[sysgrp].depends_on lvsswitchtask["#{lvs}_#{sysgrp}"] \
        if lvsswitchtask.key? "#{lvs}_#{sysgrp}"
    end

    # If we're doing reposyncs today, make the preupdate task dependent on all
    # the reposyncs.
    preupdatetask[sysgrp].depends_on reposyncdonetask if reposyncdonetask

    # Now deal with the dependencies on the tasks for the systems in
    # 'groupsystems'.
    groupsystems.each do |sys|
      # Information gathering: if the system is a VM (and not an II VM), find out
      # what its VM host is.
      vmhost = nil
      if $system[sys].non_ii_vm? and !$system[sys].updatetest
        vmhost = $system[sys].vmhost
      end

      # The OS update must depend on the group's preupdate task.
      osupdatetask[sys].depends_on preupdatetask[sysgrp]

      # If the system has the 'afternoon' label or has a 'time' label, add a
      # dependency to the appropriate task in 'timewaittask'.
      has_alarm = false
      if $system[sys].time
        osupdatetask[sys].depends_on timewaittask['time_' + $system[sys].time]
        has_alarm = true
      end

      # Now we fit the system into the checkpoint structure. However, if 'sys'
      # has an alarm-clock timer task ('has_alarm'), it can't be part of this,
      # because it will hold up the entire update process.

      # This is the last task before shutdown, so add it to the appropriate
      # shutdown checkpoint task's dependencies. This is correct whether 'sys'
      # has an alarm-clock task or not.
      systemshutdownreadytask[sys].depends_on osupdatetask[sys]

      #########################################################################
      # Group tasks: VM shutdown ready checkpoint task,
      #              non-VM shutdown ready checkpoint task
      #########################################################################

      # If 'sys' has an alarm-clock task, we're not going to involve the
      # group's shutdown-ready task so the alarm clock doesn't hold up the
      # whole group.
      unless has_alarm
        # The group can't be considered shutdown-ready until all the systems in
        # it are themselves ready for shutdown. However, if 'sys' is a VM, its
        # shutdown task can't depend on groupshutdownreadytask, because that
        # will depend on the VM host's systemshutdownreadytask, which will depend
        # on all its VMs being down, causing a circular dependency. So instead
        # we have VMs' shutdown tasks depend on a groupvmshutdownreadytask
        # checkpoint while non-VMs' shutdown tasks depend on a separate
        # groupshutdownreadytask checkpoint.
        if $system[sys].vm?
          groupvmshutdownreadytask[sysgrp].depends_on systemshutdownreadytask[sys]
          shutdowntask[sys].depends_on groupvmshutdownreadytask[sysgrp]
        else
          groupshutdownreadytask[sysgrp].depends_on systemshutdownreadytask[sys]
          shutdowntask[sys].depends_on groupshutdownreadytask[sysgrp]
        end
      end

      # In any case, the system's shutdown must wait until the system shutdown
      # ready task completes.
      shutdowntask[sys].depends_on systemshutdownreadytask[sys]

      # Other dependencies for 'shutdowntask': First, if the system is a VM host,
      # it should wait until all its VMs are shut down before shutting itself
      # down. This causes a complication: Some of a VM host's VMs may not be on
      # today's list of updates, so they will have to be shut down as well
      # (without updating).
      if ($system[sys].is_vmhost) and $vms_on_vmhost.key? sys
        # Some systems are marked 'noncompliant': that means that they won't
        # respond to this script. I should do something about those. But they
        # don't have GOC user accounts and they don't have Puppet.

        # This gets all systems labeled as being VMs on this host.
        vms = $vms_on_vmhost[sys]

        # Split 'vms' into 'today_vms' (VMs updated today) and 'not_today_vms'
        # (VMs not updated today).
        today_vms = vms.select { |vm| systems.include? vm }
        not_today_vms = vms.select { |vm| !systems.include? vm }

        # The VM host's allvmsdown task depends on all the 'today_vms' shutdown
        # tasks.
        today_vms.each do |vm|
          allvmsdowntask[sys].depends_on shutdowntask[vm]
        end

        # We'll have to create special shutdown tasks for the 'not_today_vms',
        # and the host's allvmsdown task needs to depend on those as well.
        not_today_vms.each do |vm|
          vmshutdowntask = Task.new :id => "#{vm}/shutdown",
                                    :type => :shutdown,
                                    :system => vm,
                                    :cmd => '(shutdown)',
                                    :cmdsudo => true,
                                    :timereq => $tasktime[:shutdown],
                                    :ask => true
          vmshutdowntask.depends_on groupvmshutdownreadytask[sysgrp]
          $tasklist.add vmshutdowntask
          allvmsdowntask[sys].depends_on vmshutdowntask
        end

        # The VM host can't perform its shutdown task until its allvmsdown task
        # is complete.
        systemshutdownreadytask[sys].depends_on allvmsdowntask[sys]

      elsif $system[sys].non_ii_vm?
        # The shutdown task of a VM depends on the osupdate of its host. This
        # is because the host may require one or more of its VMs to do its
        # update. (Example: cindy requires yum-internal-6, which is one of its
        # VMs.) Exception: If the host isn't being updated today, don't add
        # this dependency.
        if vmhost and systems.include? vmhost
          systemshutdownreadytask[sys].depends_on "#{vmhost}/osupdate"
        end
      end # whether it's a VM host or a VM

      # If the system is running 32-bit RHEL (and thus a PAE kernel), add a
      # task to pause and edit grub.conf, and make the shutdown task dependent
      # on that.
      if grubpausetask.key? sys
        grubpausetask[sys].depends_on osupdatetask[sys]
        systemshutdownreadytask[sys].depends_on grubpausetask[sys]
      end

      # After the reboot of the physical server ('vmhost' in the case that
      # 'sys' is a VM), we need to test and be sure we can contact each system
      # via SSH before proceeding. But before we do that, we need to wait; give
      # it time to shut down and come back up. Create a delay task depending on
      # the shutdown task, then create an ssh_test task depending on the delay
      # task.
      shutdowndelaytask[sys].depends_on shutdowntask[sys]

      # A physical server takes longer to power down and come back up, mostly
      # due to BIOS initialization
      if $system[sys].phys?
        shutdowndelaytask[sys].param = 300
        shutdowndelaytask[sys].timereq = 300
      end

      # If the machine is a VM whose host updates today, it will be poweroffed
      # and will then have to wait for the host to come up as well. Also, in
      # this case, depend on the shutdown task of the VM host
      if vmhost and systems.include? vmhost
        shutdowndelaytask[sys].param += 300
        shutdowndelaytask[sys].timereq += 300
        shutdowndelaytask[sys].deps = [ "#{vmhost}/shutdown" ]
      end

      # SSH test task depends on shutdown delay task
      sshtesttask[sys].depends_on shutdowndelaytask[sys]

      # Tasks that can only happen once an update is complete need some
      # indication of when exactly that is.
      completetask[sys].depends_on sshtesttask[sys]

      # That does it for osupdatetask[sys] and its dependencies. Now there's a
      # checkpoint to make sure that we don't proceed until all the group's
      # updates are done. Of course, systems with an alarm-clock timer task can't
      # be part of this, or they'll hold up the whole update process.
      groupdonetask[sysgrp].depends_on completetask[sys] \
        if !has_alarm and groupdonetask[sysgrp]
    end

    # Remember this group as the previous group.
    prev_sysgrp = sysgrp
  end

  # The lvsswitchtask[*_normal] tasks must depend on the last system group's
  # groupdonetask.
  if systemgroups.size > 0
    lvsservers.each do |lvs|
      lvsswitchtask["#{lvs}_normal"].depends_on groupdonetask[systemgroups.last]
    end
  end

  # We have to replace dependency placeholder strings (usually these are for
  # VMs with tasks that depend on one of the system's tasks, or VM hosts with
  # tasks that depend on one of their VMs' tasks) with references to the tasks
  # with those strings as IDs.
  $tasklist.dep_ids_to_tasks

  # We have to make sure that any VM marked 'vpnserver' isn't shut down until
  # after all the other VMs on its same host. We also have to mark its VM host
  # 'hasvpnserver'. Any physical machines marked 'vpnserver' are handled
  # differently, when we get to running the task list.
  vpnserver_shutdown_tasks = $tasklist.tasks.select do |t|
    t.type == :shutdown \
    and $system[t.system].vpnserver \
    and $system[t.system].vm?
  end

  # Get list of VM VPN servers that have shutdown tasks. While we're at it,
  # make sure each of those shutdown tasks runs last among the shutdown tasks
  # on the same VM host. That is, make it dependent on the shutdown tasks of
  # all the other VMs on the same VM host. And hey, why not, let's make a list
  # of VM hosts that have VPN servers running as VMs on them.
  vpnservers = Set.new
  vpnserver_shutdown_tasks.each do |vstask|
    # Remember that this is a VM VPN server with a shutdown task today.
    vpnservers.add vstask.system

    # Make 'task' dependent on the shutdown tasks of the other VMs on the same
    # host.
    vmhost = $system[vstask.system].vmhost
    if vmhost != '_phys' and vmhost != '_ii'
      $tasklist.select do |t|
        $system.key? t.system \
        and $system[t.system].vmhost == vmhost \
        and t.type == :shutdown \
        and t.system != vstask.system
      end.each do |shst|
        vstask.depends_on shst
      end
    end

    # Mark the VM host with the label 'hasvpnserver', so we can check for it
    # when running the task list.
    $system[vmhost].hasvpnserver = true
  end

  # Any VM with a time delay must impose a similar time delay on its host and
  # the other VMs on it; otherwise, the other VMs on the host will all be shut
  # down and unusable until the time delay occurs, causing the time-delayed VM
  # to finally be updated and shut down and the VM host to be rebooted.
  # Instead, wait on updating and shutting down the host, and all the VMs on
  # it, until the appointed time.
  $tasklist.tasks.select do |t|
    t.type == :time
  end.each do |timed_task|
    dependent_tasks = []
    timed_types = Set.new
    $tasklist.tasks.each do |other_task|
      $other_task.deps.each do |dep|
        if dep == timed_task
          dependent_tasks.push other_task
          timed_types.add other_task.type
        end
      end
    end
    # If the system is a VM host, apply the delay to the tasks of the same type
    # on the host's VMs.  If the system is a VM, apply the delay to the tasks
    # of the same type on the VM's host and all other VMs on that host.
    dependent_tasks.each do |deptask|
      sys = deptask.system
      other_systems = []
      vmhost = nil
      if $system[sys].vm?
        vmhost = $system[sys].vmhost
        other_systems.push vmhost
      elsif $system[sys].is_vmhost
        vmhost = sys
      end

      # Of course, if it's neither a VM nor a VM host, nothing else depends on
      # it, so do nothing here.
      next unless vmhost

      # Add all VMs on 'vmhost' to 'other_systems', which already contains
      # 'vmhost' if 'sys' is a VM.
      other_systems += $vms_on_vmhost[vmhost]

      other_systems.each do |other_sys|
        timed_types.each do |timed_type|
          ohtt_tasks = $tasklist.tasks.select do |t|
            t.system == other_sys
          end.select do |t|
            t.type == timed_type
          end
          ohtt_tasks.each do |ohtt_task|
            # Add timed_task to this task's dependencies.
            ohtt_task.depends_on timed_task
          end
        end
      end
    end
  end
  return 1
end

def system_is_sshable sys, jumphost = nil
  # Returns true if the given system is sshable: it exists in DNS, it's reachable
  # via the network, it responds, it allows us to log in, and it allows us to
  # execute a do-nothing command (the command is ':', in this case, which is a
  # bash no-op). If a second argument is given, will try the connection as a
  # proxy via a jumphost.
  return true if $opt.key? :test
  $sshable = Set.new
  unless $sshable.include? sys
    testcmd = nil
    if jumphost
      testcmd = "ssh -x -o \"ProxyCommand ssh #{jumphost} nc -w 120 %h %p 2>/dev/null\" #{sys} :"
    else
      testcmd = "ssh -x -o \"ConnectTimeout 5\" #{sys} :"
    end
    $sshable.add sys if system testcmd
  end
  return $sshable.include? sys
end

def mark_complete_if_ssh t
  # Mark a task complete, but first check to make sure the system can be reached
  # via SSH.  If not, prompts the user what to do. Returns true if all is well,
  # false if something went wrong.
  return nil if t.type == :shutdown
  if $opt.key? :test
    t.mark_complete
    return true
  end
  done = false
  exitval = true
  until done do
    if system_is_sshable t.system
      exitval = true
      t.mark_complete
      done = true
    else
      exitval = false
      answer = dialog_ask "(ERROR) Task '#{t.id}' could not be marked complete because ssh could not connect to #{t.system}. What do you want to do?",
                          { 'a' => '[a]bort: Abort immediately',
                            'e' => '[e]xit: Save progress and exit',
                            'm' => '[m]anual: Type this after doing task manually',
                            'r' => '[r]etry: Try the ssh connection again',
                            's' => '[s]kip: Skip task for now' }
      if answer == 'a'
        fin
        exit 1
      elsif answer == 'e'
        save_and_exit
      elsif answer == 'm'
        t.mark_complete
        t.manual = true
        done = true
      elsif answer == 's'
        t.skip = true
        done = true
      end
    end
  end
  return exitval
end

def check_windows
  # Using $tasklist, check tmux for windows that are still open, dealing with
  # the ones that have closed. In test mode, consider all windows already
  # closed. This marks tasks complete whose windows have closed. Returns number
  # of tasks marked complete.

  open_windows = Set.new
  if $opt.key? :test
    # In test mode, consider windows to have closed already (since they were
    # never actually opened).
  else
    open_windows = (TmuxUtils::all_window_ids $tmux_session.id).to_set
  end
  # Now go through all tasks that have a tmux_window set, and if a task's
  # tmux_window no longer exists in tmux, delete it from the task and mark the
  # task complete.
  count = 0
  $tasklist.tasks.each do |t|
    # Skip tasks that don't have tmux windows.
    next unless t.tmux_window
    test = false
    # In test mode, the window will never be in open_windows, as we're
    # considering all windows already closed.
    unless $opt.key? :test
      test = (open_windows.include? t.tmux_window.id)
    end
    unless test
      # This task says it has a tmux window, but it's not on the list of open
      # windows (anymore). Thus it has closed and is complete.
      t.tmux_window = nil
      # Here's where we mark tasks complete.
      count += 1
      if t.type == :shutdown
        # Most of the time we check to see whether the system is online before
        # marking a task complete, but this makes no sense if the task is of
        # type "shutdown", since the goal of the task is to cause the system not
        # to be online. Just mark it complete if the command was executed.
        complete_task t
      else
        # (Why do we not just mark it complete? There's a separate ssh_test
        # task that tests for ssh connectivity. I seem to recall trying to
        # forego this check in the past, though, and undoing it because it
        # caused problems. If this causes problems again, restore the commented
        # mark_complete_if_ssh line and comment or remove the t.mark_complete
        # line.)
        #
        # mark_complete_if_ssh t
        t.mark_complete
      end
    end
  end
  return count
end

def count_known_windows
  # Returns a count of the known open windows from $tasklist.
  return $tasklist.tasks.select { |t| !t.tmux_window.nil? }.size
end

def do_remote_command target, cmd, use_jumphost = false
  # SSHes to the given target system to perform the given command. If the
  # optional third argument is present and true, uses a jumphost. Returns an
  # array of the output lines, or nil if there was an error.

  ssh_cmd = ''
  if use_jumphost
    # Figure out which jumphost to use, starting by getting a list of the
    # jumphosts that exist. Also, in the case that 'target' is itself a
    # jumphost, we don't want it to use itself as a jumphost.
    potential_jumphosts = $system.select do |s, d|
      d.jumphost
    end.keys
    # Is 'target' a VM or not?
    if $system[target].non_ii_vm?
      # Find out what 'target's VM host is.
      vmhost = $system[target].vmhost
      # We probably don't want the jumphost to be 'vmhost' or any of the VMs on
      # it.
      potential_jumphosts.reject! { |s| s == vmhost or $system[s].vmhost == vmhost }
    else
      # 'target' isn't a VM, so it's a physical server, so it's either a VM
      # host itself or some other server. If it's a VM host, we don't want the
      # jumphost to be one of its VMs. If it's a physical server, it's all
      # good.
      if $system[target].is_vmhost
        potential_jumphost.reject! { |s| $system[s].vmhost == target }
      end
    end
    # Just pick one of the jumphosts; any of them is fine.
    jumphost = potential_jumphosts.sample
    ssh_cmd = sprintf 'ssh -x -tt -o "ProxyCommand ssh %s nc -w 120 %%h %%p 2>/dev/null" %s "%s"',
                      jumphost, target, (doublequote_escape cmd)
  else
    ssh_cmd = sprintf 'ssh -x -tt %s "%s" 2>/dev/null',
                      target, (doublequote_escape cmd)
  end
  return `#{ssh_cmd}`.split "\n"
end

def generate_shutdown_cmd sys, msg = nil, restart = false
  # Given a system, generates a shutdown command for that system. The optional
  # second argument, if present, will be appended to the shutdown message
  # broadcast to users on 'system'. If the optional third argument is true,
  # generates a restart command rather than a shutdown command. Tests to see if
  # anyone is logged in on the system; if so, gives shutdown a 5-minute delay to
  # warn them. If no one is logged in, the shutdown/restart happens
  # immediately.
  if msg
    msg = ' ' + msg
  else
    msg = ''
  end
  actionarg = '-h -P'
  participle = 'Shutting down'
  if restart
    actionarg = '-r'
    participle = 'Restarting'
  end
  delayarg = ' now'
  unless $opt.key? :test
    # See if anyone's logged in.
    output = do_remote_command sys, 'w -sh'
    # If so, give them 5 minutes.
    if output.size > 1
      delayarg = ' +5'
    end
  end
  cmd = "/sbin/shutdown #{actionarg}#{delayarg} \"#{participle} #{sys}#{msg}\""
  return cmd
end

def do_backend_cmd t
  # Do a single task. That is, start a tmux window to do it. The task is
  # guaranteed not to be a subroutine task; it will require a tmux window.
  # Won't open more tmux windows if '$max_windows' would be exceeded. Returns
  # true if it was possible to run the command and false otherwise.

  # Check 't'.
  unless t.kind_of? Task
    outputs "*** In do_backend_cmd: Argument isn't a Task (is #{t.class})."
    return false
  end

  # Don't exceed '$max_windows'. No need to do anything but return false here;
  # the calling routine will just try again next iteration, when with any luck
  # some windows will have completed and closed.
  return false if count_known_windows >= $max_windows

  # Get command.
  unless t.cmd
    outputs "*** In do_backend_cmd: Task's cmd is nil."
    return false
  end
  cmd = t.cmd

  # Get system.
  unless t.system
    outputs "*** In do_backend_cmd: Task's system is nil."
    return false
  end
  sys = t.system

  # Unless $opt[:yes] is set, add bash for verification, unless 'type' is
  # :shutdown.
  unless $opt.key? :yes
    unless t.type == :shutdown
      cmd = sprintf '%s; bash', cmd
    end
  end
  # Wrap in a 'bash -c' for safety of compound commands and I/O redirects.
  bash_cmd = sprintf 'bash -c "%s"', (doublequote_escape cmd)
  if t.cmdsudo
    bash_cmd = sprintf '/usr/bin/sudo -Hi -- %s', bash_cmd
  end

  # Wrap 'bash_cmd' in an ssh command to be performed on 'sys' (possibly via a
  # jump host).
  ssh_cmd = nil
  # If this is a 'shutdown' task, any system labeled 'hasvpnserver' will have to
  # be contacted via a jump host; a direct connection will probably not work
  # because of the VPN server's being down. However, that jump host can't be
  # one that's currently being updated.
  if t.type == :shutdown and $system[sys].hasvpnserver
    # This is a 'shutdown' task, and the system has a VPN server on it, so we'll
    # need a jump host, and moreover, one that isn't on this system.
    jumphost = $system.select { |s, d| d.jumphost and d.vmhost != sys }.keys.sample
    unless jumphost
      outputs "*** In do_backend_cmd: Unable to find a jumphost to get to #{sys}."
      return false
    end
    ssh_cmd = sprintf 'ssh -x -tt -o "ProxyCommand ssh %s nc -w 120 %%h %%p 2>/dev/null" %s "%s"',
                      jumphost, sys, (doublequote_escape bash_cmd)
  else
    # We don't need a jump host, either because this isn't a 'shutdown' task
    # (if we aren't shutting down anything, then we aren't shutting down the
    # VPN server's system) or because this isn't a VM host that has a VPN host
    # running on it as a VM.
    ssh_cmd = sprintf 'ssh -x -tt %s "%s"',
                      sys, (doublequote_escape bash_cmd)
  end

  # Wrap 'ssh_cmd' in a tmux command so it's performed in a tmux window.
  # Key to 'tmux neww' options:
  # -d: detach; don't switch screen to new window
  # -P: print info about newly created window
  # -F <fmt>: format info that -P prints;
  #     #S is session name and #I is window index
  # -t <target_window>: window to create;
  #     format is '<session name>:<window index>',
  #     but if you omit <window_index>,
  #     it generates a new index
  # -n <window_name>: names the new window
  t.mark_started

  refresh_selectable_tasks
  refresh_taskwin
  refresh_status
  $cui.refresh

  if $opt.key? :test
    # In test mode no actual window gets opened so just make up a bogus window
    # ID.
    t.tmux_window = "#{sys}:#{t.type}:#{Time.now.to_i}"
    debug_outputs "Command: #{ssh_cmd}"
    $cui.refresh
  else
    t.tmux_window = $tmux_session.new_window :detach => true,
                                             :window_name => sys,
                                             :shell_command => (doublequote_escape ssh_cmd)
  end
  return true
end

def allvmsdown task
  # Can be called as the cmd in a task. Returns true if all the VMs on the
  # given task's VM host are down (or if it isn't a VM host), and false if any
  # of them are up. Always returns true if run in test mode (-t).

  outputs ">>> ENSURING all VMs down on VM host '#{task.system}'"
  return true if $opt.key? :test
  return !(any_vm_up task.system)
end

def uncomplete_task id
  # Mark Task with given id incomplete.

  $tasklist.tasks.select { |t| t.id == id }.each do |t|
    t.complete = false
  end
end

def complete_task arg
  # Mark Task, or Task with given id, complete. The only difference between
  # calling t.mark_complete on the task and calling this method is that you can
  # call this method with either a task or an id.

  tasks = []
  if arg.kind_of? Task
    tasks.push arg
  else
    tasks += $tasklist.tasks.select { |t| t.id == id }
  end
  tasks.each do |t|
    t.mark_complete
  end
end

def force_manual task
  # Called when a task that would normally be performed on a system must be done
  # manually. For example, if it's a jump host, on which sudo is disabled, but
  # the command must be done with sudo.

  outputs ">>> MANUAL ASSISTANCE REQUIRED for system '#{task.system}'"
  response = dialog_ask "You will have to manually become root on #{task.system} and enter a command like '#{task.cmd}'.",
                        { 'd' => '[d]one', 'q' => '[q]uit' }

  return nil if response == 'q'
  return true
end

def grub_pause task
  # Can be called as the cmd in a task. Tells the user that they might want to
  # update /etc/grub.conf on the system in the task before its imminent reboot.
  outputs ">>> PAUSING for sysadmin to check grub.conf on system '#{task.system}'"
  response = dialog_ask "You may want to check /etc/grub.conf on #{task.system}.",
                        { 'd' => '[d]one', 'q' => '[q]uit' }
  return nil if response == 'q'
  return true
end

def lvs_switch task
  # Can be called as the cmd in a task. Runs the appropriate command on the LVS
  # servers so the other tasks will be able to update the given group with
  # minimal downtime. If the task's system is 'normal' rather than 'groupX',
  # that means it's time to return LVS to normal.

  return true if task.param == 'ungrouped'
#  msg = ''
  if task.param == 'normal'
    outputs ">>> SWITCHING LVS back to normal"
#    msg = 'It is now time to return LVS to normal.'
  else
    outputs ">>> SWITCHING LVS so as to shunt network traffic away from #{group}"
#    msg = "It is now time to switch LVS so as to shunt network traffic away from #{group}."
  end
#  response = dialog_ask msg, { 'd' => '[d]one', 'q' => '[q]uit' }
#  return nil if response == 'q'
  return true if $opt.key? :test
  bash_cmd = sprintf 'bash -c "%s"', (doublequote_escape task.cmd)
  bash_cmd = sprintf '/usr/bin/sudo -Hi -- %s', bash_cmd
  ssh_cmd = sprintf 'ssh -x -tt %s "%s"',
                    sys, (doublequote_escape bash_cmd)
  result = system ssh_cmd
#  %w(lvs1.goc lvs2.goc).each do |sys|
#    ssh_cmd = sprintf 'ssh -tt %s "%s"',
#                      sys, (doublequote_escape bash_cmd)
#    result &&= system ssh_cmd
#  end
  return result
end

def ssh_test task
  # Can be called as the cmd in a task. Tests whether we can ssh to the task's
  # system.
  outputs ">>> CONFIRMING that system '#{task.system}' can be reached via SSH ..."
  return true if $opt.key? :test
  result = system "ssh -x -o 'ConnectTimeout=2' #{task.system} /bin/true"
  if result == true
    outputs "Yes"
  else
    outputs "No"
  end
  return result
end

def checkpoint task
  # Can be called as the cmd in a task. Does nothing but return true. This is a
  # placeholder to allow other tasks to depend on whether this one is complete,
  # creating a checkpoint in the process, nothing more. Prints the task's
  # 'param' property.
  param = task.param || '(not set)'
  outputs ">>> CHECKPOINT: #{param}"
  return true
end

def complete task
  # Can be called as the cmd in a task. Does nothing but return true. Similar
  # to 'checkpoint', this is used as a placeholder to allow other tasks to
  # depend on whether a given system's updates are all complete.
  outputs ">>> DECLARING system '#{task.system}' complete"
  return true
end

def delay task
  # Can be called as the cmd in a task. There is no specific label that causes
  # this task to occur; it happens between shutdown tasks and sshtest tasks.
  # We want to make sure to delay at least the amount of time (seconds) in the
  # task's param. If the task's timestamp isn't set, set it to the current time
  # plus param seconds and return false; the delay has only just begun. If the
  # timestamp is set, compare the current time to it, and if it's greater than
  # or equal to it, return true; the delay is over. Otherwise return false; the
  # delay is still in progress.
  had_timestamp = !task.timestamp.nil?
  result = nil
  if had_timestamp
    result = task.delay_complete?
    if result
      outputs ">>> DELAY FINISHED on system '#{task.system}'"
    else
      outputs ">>> STILL DELAYING on system '#{task.system}'"
    end
  else
    # Didn't have a timestamp, so timer is "unstarted." Start it.
    task.param = 0 if $opt.key? :test
    result = task.delay_start
    unless result
      outputs "*** WARNING: #{task.status}"
      return nil
    end
    # We will be returning a false value indicating that the delay has not
    # completed yet.
    result = false
    outputs ">>> STARTED DELAY for #{task.param/60} minutes #{task.param%60} seconds on system '#{task.system}'"
  end
  return result
end

def timewait task
  # Can be called as the cmd in a task. Returns true if we have passed the
  # target time in the task's parameter, in the timezone in the task's
  # parameter, on the date it is in that timezone. Pays attention to Daylight
  # Saving Time, British Summer Time, and other similar date-based timekeeping
  # contrivances, if they're part of the given time zone info. Returns false if
  # it isn't time yet. Returns undef if there was an error.
  return true if $opt.key? :test
  result = task.timewait_complete
  if result
    outputs ">>> WAIT OVER on system '#{task.system}'"
    return true
  else
    outputs ">>> WAITING until #{task.param} before continuing on system '#{task.system}'"
    return false
  end
end

def perform_task t, ts = Time.now
  # Perform a single task. That is, start a tmux window to do it. Return true
  # if we were able to do so, false if not. The return value has nothing to do
  # with the success or failure of the task itself, just whether this method
  # was able to get it started. The first argument is the Task object, and the
  # second is the Time when we want to say the attempt occurred.

  unless t.kind_of? Task
    outputs "*** In #{__method__}: Argument not a Task"
    return false
  end
  unless t.cmd
    outputs "*** In #{__method__}: Argument doesn't have a .cmd attribute"
    return false
  end

  # Set things up.
  t.lastattempt = ts
  cmd = t.cmd
  result = nil

  # Differentiate "&" tasks from normal tasks.
  if cmd.start_with? '&'
    # This isn't a command, per se; it's a method call. They're handled
    # differently. They don't get executed in tmux windows, for one thing.
    t.mark_started

    # Refresh the task window so we can see the task change state.
    refresh_selectable_tasks
    refresh_taskwin
    refresh_status
    $cui.refresh

    # Call the method in the task, which is just cmd minus the initial "&". Do
    # this within begin ... end so we can rescue the case where the method
    # doesn't exist for some reason.
    begin
      result = (method cmd[1..-1].to_sym).call t
    rescue NoMethodError => err
      outputs "*** In #{__method__}: Unknown task type '#{cmd}' (no method #{cmd[1..-1].to_sym})"
      return false
    end

    # If the method came back with a true result, mark the task complete. All
    # such methods must return true on success and false or nil on failure.
    if result
      complete_task t
    else
      # Timers (delays and alarms) aren't really failures if they return false;
      # it just means their time has not yet come.
      if t.timer?
        result = true
      elsif cmd == '&grub_pause' # There shouldn't be any of these anymore.
        save_and_exit
      else
        # True failure: increment the fail counter and set the lastfail
        # timestamp. Also unmark the task started so it will be picked up again
        # on the next attempt or can at least be selected again.
        debug_outputs "Attempted #{t.id}, but it failed."
        if t.failcount.nil?
          t.failcount = 1
        else
          t.failcount += 1
        end
        t.lastfail = t.lastattempt
        t.unmark_started
      end
    end
  else # i.e. if 'cmd' doesn't start with '&' and is thus a regular command
    # If we can't ssh/sudo to the system, we'll have to ask the user to do it
    # manually. This is if the system is a jumphost and the task requires sudo,
    # or if the system is noncompliant with GOC standards (which shouldn't be,
    # but nevertheless sometimes is).
    if ($system[t.system].jumphost and t.cmdsudo) \
      or $system[t.system].noncompliant
      result = force_manual t
      if result.nil?
        # If the user selected quit ...
        save_and_exit
      end
      # The user said it was done, so we'll trust that they did it.
      complete_task t
    else
      # Most of the time we go here.
      if t.type == :shutdown
        # Now, we didn't set 'cmd' for 'shutdowntask', so that's what we're
        # going to do now. If this is a non-II VM whose host is updating today,
        # power the system off; it will come back up with the host reboots. If
        # it's not a VM, if it's an II VM, or if it's a VM whose host isn't
        # updating today, just reboot the machine. If it's not a :shutdown
        # task, there's nothing special we need to do here.
        if $system[t.system].phys? or $system[t.system].ii_vm?
          # Not VM, or II VM
          t.cmd = generate_shutdown_cmd t.system,
                                        'for OS updates; back shortly',
                                        true
        else
          # Non-II VM
          vmhost = $system[t.system].vmhost
          raise RuntimeError.new "System '#{t.system}' is marked as a VM but its location is nil" if vmhost.nil?
          if $system[vmhost].day == $update_day
            # Non-II VM whose host is updating today
            t.cmd = generate_shutdown_cmd t.system,
                                          'due to OS updates on its virtualization host; back shortly',
                                          false
          else
            # Non-II VM whose host isn't updating today
            t.cmd = generate_shutdown_cmd t.system,
                                          'for OS updates; back shortly',
                                          true
          end
        end
      end
      # Execute the actual ssh command on the host. Unfortunately "result" is
      # not always reliable, so don't decide what to do based on this.
      result = do_backend_cmd t
    end
  end # if cmd.start_with? '&'
  return result
end

def should_attempt t
  # Should the failed task t be attempted? Ordinarily this means:
  #
  # * the task is startable
  #
  # * if the task has been attempted before and has failed, it's been long
  #   enough since the last failure, according to the global $retry_delay
  #   setting -- don't continuously retry failed tasks

  # Is the task startable? (It mustn't be marked complete, its dependencies
  # must all be met, it can't be an alarm task, and it mustn't be marked
  # started.)
  return false unless t.startable?

  # We'll only be here at all if t is startable. The seconds_since_fail method
  # will return nil if the task is marked complete (should have been weeded out
  # by the startable? test above), has a zero failcount, or has a nil lastfail
  # timestamp. If there's been no history of failure, go ahead; return true.
  ssf = t.seconds_since_fail
  return true if ssf.nil?

  # ssf has a non-nil value, hopefully a floating-point number of
  # seconds. Compare that result with $retry_delay. Return true if it last
  # failed less recently than $retry_delay seconds ago (i.e. return false if it
  # last failed more recently than that).
  return ssf > $retry_delay
end

def perform_selected_tasks
  # Quick utility method to perform $selected_tasks, a Set of tasks that was
  # selected by the user from $selectable_tasks. Returns number of tasks
  # successfully performed.

  count = 0
  $selected_tasks.to_a.each do |t|
    next unless t.deps_met?

    # See if the task has been tried and failed too recently, according to
    # $retry_delay.
    next unless should_attempt t

    if perform_task t, Time.now
      count += 1
    else
      outputs "Task '#{t.id}' failed. It has not been marked complete and will be retried shortly."
      # perform_task marks a task started, not knowing whether it will
      # subsequently succeed or fail. If it fails, let's unmark it started, so
      # it will be seen and tried again.
      t.unmark_started
    end
  end
  return count
end

def perform_trivial_tasks
  # Quick utility method that performs all startable trivial tasks, defined as
  # tasks for which the ask? method is false and that are not timers. Returns
  # number of tasks successfully performed.

  count = 0
  loop do
    any_tasks = false
    $tasklist.select do |t|
      !t.ask and !t.timer? and (should_attempt t)
    end.each do |t|
      any_tasks = true
      if perform_task t, Time.now
        count += 1
      else
        outputs "Task '#{t.id}' failed. It has not been marked complete and will be retried shortly."
      end
    end
    break unless any_tasks
  end
  return count
end

def start_startable_timers
  # Quick utility method that starts all startable timers (with timers there's
  # an understanding that they will not complete as soon as they are started,
  # unlike other tasks that don't actually make an ssh connection or run a
  # command). Returns number of timers started.

  count = 0
  $tasklist.select do |t|
    t.timer? and t.startable?
  end.each do |t|
    count += 1
    perform_task t, Time.now
  end
  return count
end

def activity_mode_perform_selected_tasks
  # When the user has told us to go forth and perform whatever tasks they've
  # selected, this is what we do.

  # Clear up any windows that have closed.
#  check_windows
  # Perform the $selected_tasks.
  perform_selected_tasks
  # Now clear all trivial tasks out of the way.
#  check_windows
#  perform_trivial_tasks
  # Now start all startable timers.
#  start_startable_timers
  # Refresh everything after doing that.
#  check_windows
#  refresh_selectable_tasks
#  refresh_status
#  refresh_taskwin
#  $cui.refresh

  # We're done. Go back to waiting for the user to tell us what to do next.
#  $activity_mode = nil
end

def get_vm_states vmhost
  # Given a VM host, return a hash whose keys are the VM names and whose values
  # are the strings 'up' or 'down'.
  lsvm = `ssh -x #{vmhost} '/opt/sbin/lsvm -n' 2>&1`.split "\n"
  state = {}
  return state if lsvm.first =~ /no such file or directory\s*$/i
  lsvm.each do |line|
    (vm, st) = line.split(/\s+/)
    state[vm] = st
  end
  return state
end

def any_vm_up vmhost
  # Given a VM host, see if any VMs are up on it. Return true if there are any,
  # false if there aren't (or if it isn't a VM host).

  any = false
  (get_vm_states vmhost).each do |vm, st|
    if st == 'up'
      any = true
      break
    end
  end
  return any
end

def write_tasklist
  # Write $tasklist to $savefile.
  begin
    File.write $savefile, (YAML.dump $tasklist)
  rescue Errno::EACCES => err
    outputs err.to_s
    $cui.refresh
    return nil
  end
  return true
end

def write_tasklist_with_protection
  # Save the tasklist, with protection in case the save fails somehow. Don't
  # save in test mode.
  return if $opt.key? :test
  loop do
    result = write_tasklist
    return if result
    response = dialog_ask "Error saving tasklist. Try again?",
                          {
                            'y' => '[y]es',
                            'n' => '[n]o' }
    break if response == 'n'
  end
end

def save_and_exit
  # Save the tasklist and exit.
  write_tasklist_with_protection
  fin
  exit 0
end

def refresh_status
  # As a way of reporting how things are going (rather than just printing no
  # output unless there's an error, then showing an unreassuring prompt when
  # it's all over), print a table showing how many of each type of task are
  # complete, paying special attention to how many tasks of type "complete"
  # there are and how many of the "complete" tasks are complete.

  count = Hash.new 0
  complete = Hash.new 0
  $tasklist.tasks.each do |t|
    count[t.type] += 1
    complete[t.type] += 1 if t.complete?
  end
  $statwin.clear
  $statwin.puts "Current status report:"
  count.keys.sort.each do |type|
    next if type == :complete
    $statwin.puts (sprintf "%s: %d/%d (%.02f%%)",
                           type, complete[type], count[type],
                           100.0*(complete[type].to_f/count[type].to_f))
  end
  if count.key? :complete and count[:complete] > 0
    $statwin.puts (sprintf "*** %d/%d (%.02f%%) systems complete",
                           complete[:complete], count[:complete],
                           100.0*(complete[:complete].to_f/count[:complete].to_f))
  else
    $statwin.puts "*** count[:complete] is 0"
  end
  $statwin.puts
  $statwin.noutrefresh
end

def refresh_selectable_tasks
  # Refresh $selectable_tasks. This is just the list of tasks that have no
  # unmet dependencies and have not been marked complete. This should be called
  # before accepting keyboard/mouse input on what to do next.

  # Do not change $selectable_tasks while refreshing the task window.
  sleeptime = 0.1
  while $refreshing_taskwin
    sleep sleeptime
    sleeptime *= 2.0
    sleeptime = 10.0 if sleeptime > 10.0
  end

  # If the $task_cursor was pointed at a task that is still in the list, we
  # want it to stay pointed at that task, even if its position has changed due
  # to other tasks disappearing or new tasks appearing. So remember the task
  # that $task_cursor was pointed at before we go changing the contents of
  # $selectable_tasks. Remember the first unselected ones before and after it,
  # just in case.
  cursor_task = nil
  cursor_task_pred = nil
  cursor_task_succ = nil
  if $task_cursor and $selectable_tasks.size > 0
    cursor_task = $selectable_tasks[$task_cursor]
    ($task_cursor...$selectable_tasks.size).each do |i|
      next if $selected_tasks.include? $selectable_tasks[i]
      cursor_task_succ = $selectable_tasks[i]
      break
    end
    $task_cursor.downto(0) do |i|
      next if $selected_tasks.include? $selectable_tasks[i]
      cursor_task_pred = $selectable_tasks[i]
      break
    end
  end

  # Now rebuild $selectable_tasks. If $show_all_tasks is true, just make it the
  # list of tasks that aren't complete. But normally, this should be the list
  # of tasks that are either startable (i.e. not complete and have all
  # dependencies met), or started-but-not-complete.
  $selectable_tasks = $tasklist.select do |t|
    if $show_all_tasks
      !t.complete?
    else
      t.startable? or (t.started? and !t.complete?)
    end
  end

  # Now try to place the cursor where it was before (on cursor_task). If
  # cursor_task is no longer in $selectable_tasks, place it on
  # cursor_task_succ. If we don't have a cursor_task_succ, try
  # cursor_task_pred, and if that doesn't work, place it on the first task, or
  # on nil if there are no tasks in $selectable_tasks.
  if cursor_task and $selectable_tasks.include? cursor_task
    $task_cursor = $selectable_tasks.index cursor_task
  elsif cursor_task_succ and $selectable_tasks.include? cursor_task_succ
    $task_cursor = $selectable_tasks.index cursor_task_succ
  elsif cursor_task_pred and $selectable_tasks.include? cursor_task_pred
    $task_cursor = $selectable_tasks.index cursor_task_pred
  else
    if $selectable_tasks.size > 0
      $task_cursor = 0
    else
      $task_cursor = nil
    end
  end

  # As for $selected_tasks, we want the same tasks to be selected, minus the
  # ones that are no longer in $selectable_tasks.
  $selected_tasks = $selected_tasks & $selectable_tasks.to_set
end

def print_task_line i, cursor
  # Prints the line in the task window that appears for each task there.

  t = $selectable_tasks[i]
  if t.nil?
    outputs "ERROR: Nil task line (i = #{i}, cursor = #{cursor})"
    outputs "    Stack: #{caller.join ', '}"
    return
  end
  select_char = ''
  if $selected_tasks.include? t
    select_char = "\u2611"
  else
    select_char = "\u2610"
  end
  cursor_attr = 0
  if !cursor.nil? and cursor == i
    cursor_attr = Curses::A_REVERSE
  end
  $taskwin.attrset $cp_normal.to_cp | Curses::A_BOLD | cursor_attr
  $taskwin.addstr "#{select_char} #{t.id} "
  if t.started?
    $taskwin.attrset $cp_white_on_green.to_cp | Curses::A_BOLD | cursor_attr
    $taskwin.addstr 'RUNNING'
    if t.timer?
      $taskwin.attrset $cp_normal.to_cp | Curses::A_BOLD | cursor_attr
      $taskwin.addstr " (#{t.timer_remaining} sec)"
    end
  else
    $taskwin.attrset $cp_white_on_red.to_cp | Curses::A_BOLD | cursor_attr
    $taskwin.addstr 'waiting'
  end
  if t.unmet_deps.size > 0
    $taskwin.attrset $cp_normal.to_cp | Curses::A_BOLD | cursor_attr
    $taskwin.addstr " (#{t.unmet_deps.size} unmet deps)"
  end
  $taskwin.puts
end

def output_task_deps t
  # Print task dependencies to output window
  isornot = (t.complete?)? 'is' : 'is not'
  depids = t.deps.map { |d| "'#{d.id}' (#{(d.complete?)? 'complete' : 'incomplete'})" }.join ', '
  outputs "Task '#{t.id}' #{isornot} complete and has dependencies: #{depids}"
end

def refresh_task_cursor old, new
  $taskwin.setpos old, 0
  print_task_line old, new
  $taskwin.setpos new, 0
  print_task_line new, new
  $taskwin.noutrefresh
end

def refresh_taskwin
  # Refresh display of task list.

  $refreshing_taskwin = true
  $taskwin.clear
  unless $task_cursor.nil?
    # Clamp $task_cursor within [0, $selectable_tasks.size - 1]
    $task_cursor = 0 if $task_cursor < 0
    $task_cursor = ($selectable_tasks.size - 1) if $task_cursor >= $selectable_tasks.size
    $selectable_tasks.sort { |a, b| a.id <=> b.id }.each_index do |i|
      print_task_line i, $task_cursor
    end
    # If the $task_cursor isn't in the window, scroll it so it is.
    if $task_cursor < $taskwin.pad_y
      $taskwin.pad_y = $task_cursor
    elsif $task_cursor >= $taskwin.pad_y + $taskwin.pad.height
      $taskwin.pad_y = $task_cursor - $taskwin.pad.height + 1
    end
    $taskwin.setpos $task_cursor, 0
    print_task_line $task_cursor, $task_cursor
  end
  $taskwin.noutrefresh
  $refreshing_taskwin = false
end

def do_test
  # A threaded method to use for testing.
  answer = dialog_ask "This is a test question. Please answer yes or no.",
                      {
                        'y' => '[y]es',
                        'n' => '[n]o' }
  if answer == 'y'
    outputs "You answered yes."
  elsif answer == 'n'
    outputs "You answered no."
  else
    outputs "You answered something else somehow."
  end
  $cui.refresh
end

def do_systemdata
  # This is the part where we read systemdata.yaml, contact all the VM hosts to
  # find out what hosts all the VMs are on, etc.
  read_dns_cache
  refresh_systemdata
  write_dns_cache
  unless check_systemdata
    fin
    exit 1
  end
  write_systemdata
end

def do_build_tasklist
  # Here we obtain the $tasklist, whether from the save file or by constructing
  # it.

  maybe_read_tasklist
  unless $tasklist.size > 0
    unless $update_day or $opt.key? :cmds
      debug_push "Today is not an update day ... doing nothing"
      fin
      exit 0
    end
    unless build_task_list
      fin
      exit 1
    end
  end
  unless $tasklist.size > 0
    debug_push "Somehow there are no tasks at all ... odd"
    fin
    exit 1
  end
  unless check_tasks
    debug_push "Unable to continue."
    fin
    exit 1
  end
  outputs ">>> TASKLIST COMPLETE"
#  begin
#    task = $tasklist.find_task_by_id 'ruckus/allvmsdown'
#  rescue RuntimeError => e
#    str = e.to_s + "\n" + (e.backtrace.join "\n")
#    outputs str
#  else
#    outputs task.to_s
#  end
end

def do_activity_loop
  # This is the "main loop" method, the method to call once the data is
  # collected and the tasklist is built. Another thread is running the UI (and
  # responding to keystrokes), so this one has to poll the $activity_mode
  # global, which is that thread's way of telling this one what the user wants
  # to do. Now we are either waiting for the user to tell us to do something,
  # or doing something the user told us to do.

  # This does mean that we'll have to take measures to make sure we're not
  # constantly refreshing the display over and over, wasting time and making
  # the screen look crappy. But we also can't look like we're unresponsive to
  # user keystrokes.

  debug_outputs "In do_activity_loop."
  refresh_selectable_tasks
  refresh_status
  refresh_taskwin
  $cui.refresh

  # Loop until we break out.
  loop do
    # Get the number of undone tasks remaining. If there aren't any, we're
    # done; break out of the loop.
    tasks_remaining = $tasklist.undone.size
    break if tasks_remaining == 0

    # There are undone tasks. Decide what to do based on $activity_mode, which
    # should have been set to something before this method was called.
    debug_outputs "Activity mode: #{$activity_mode}" unless $activity_mode.nil?
    case $activity_mode
    when :perform_selected_tasks
      # In :perform_selected_tasks mode, perform the selected tasks.
      perform_selected_tasks
      refresh_selectable_tasks
      refresh_status
      refresh_taskwin
      $cui.refresh
      $activity_mode = nil
    when :refresh_tasks
      refresh_selectable_tasks
      refresh_status
      refresh_taskwin
      $cui.refresh
      $activity_mode = nil
    when :mark_selected_tasks_complete
      $selected_tasks.to_a.each do |t|
        t.mark_started
        complete_task t
        outputs ">>> MANUAL: Task '#{t.id}' marked complete."
        t.manual = true
      end
      refresh_selectable_tasks
      refresh_status
      refresh_taskwin
      $cui.refresh
      $activity_mode = nil
    when :exit_activity_loop
      # This is when the user presses 'q'.
      $cui.exit_event_loop
      $activity_mode = nil
      break
    when :exit_activity_loop_and_save
      # This is when the user presses 'e' or 'x'.
      $cui.exit_event_loop
      write_tasklist_with_protection
      $activity_mode = nil
      break
    when nil
      # This is if the user didn't press anything. We shouldn't immediately
      # continue; other tasks need time. But we don't need to pause so long
      # that the user would notice.
      sleep 0.1
    else
      # Somehow $activity_mode is set to something other than one of the above
      # symbols or nil.
      debug_outputs "$activity_mode is set to unrecognized value #{$activity_mode}."
      $activity_mode = nil
    end
  end
  # Should only be here once all tasks are complete (or if the user has pressed
  # a key that exits the loop, like 'q', 'e', 'x', etc.).
  outputs "All tasks complete. Press Q to exit."
end

def do_end_pause
  # Called as a thread by manage_threads after do_activity_loop is done. Just
  # wait for the user to press Q.

  refresh_selectable_tasks
  refresh_status
  refresh_taskwin
  $cui.refresh

  # Loop until we break out.
  loop do
    case $activity_mode
    when :exit_activity_loop
      # This is when the user presses 'q'.
      $cui.exit_event_loop
      fin
      exit 0
    when nil
      # This is if the user didn't press anything. We shouldn't immediately
      # continue; other tasks need time. But we don't need to pause so long
      # that the user would notice.
      sleep 0.1
    else
      # The user pressed something other than 'q' that would be recognized in
      # do_activity_loop, but not here.
      $activity_mode = nil
    end
  end
end

def thread_running_callback
  # Runs if $thread is non-nil and running. This method itself isn't run as a
  # thread, so anything that blocks here will block manage_threads.

  # Don't run too often.
  $trc_last_run = Time.new if $trc_last_run.nil?
  return if Time.new - $trc_last_run < 0.1

  # Check any tmux windows, start any timers, and perform any trivial tasks.
  task_changes = 0
  task_changes += check_windows
  task_changes += perform_trivial_tasks
  task_changes += start_startable_timers

  # If any of that caused anything to happen, refresh everything.
  if task_changes > 0
    refresh_selectable_tasks
    refresh_taskwin
    refresh_status
    $cui.refresh
  end
  $trc_last_run = Time.new
end

def manage_threads
  # The event loop's callback goes here. This allows messages to go to the UI's
  # windows even before keystrokes are being handled. See if the main $thread
  # is running -- if it is, return. If not, move on to the next $step and call
  # that method in $steps as the new main $thread. As always, any output goes
  # to $outwin.

  Thread.abort_on_exception = true
  if !$thread.nil? and $thread.alive?
    thread_running_callback
    return
  else
    $step += 1
    if $step >= $steps.size
      sleep 0.1
      return
    end
    $thread = Thread.new { method($steps[$step]).call }
  end
end

def handle_key event
  raise RuntimeError.new "Event was not a KeyEvent (was a #{event.class})" unless event.kind_of? Curses::Ui::KeyEvent
  handled = false

  # Keystrokes specific to a window go here -- if the same keystroke is also
  # handled generically but you don't want that generic effect to happen, set
  # handled to true.
  if $cui.focus == $taskwin
    if event.ch == Curses::Key::DOWN or event.ch == Curses::Key::NEXT
      if $selectable_tasks.size > 0
        # Move task cursor one line down.
        new_task_cursor = [ $task_cursor + 1, $selectable_tasks.size - 1 ].min
        # Make sure the task cursor is visible.
        $task_cursor = new_task_cursor
        refresh_taskwin
        $cui.focus.noutrefresh
        $cui.refresh
        handled = true
      end
    elsif event.ch == Curses::Key::UP or event.ch == Curses::Key::PREVIOUS
      if $selectable_tasks.size > 0
        # Move task cursor one line up.
        new_task_cursor = [ $task_cursor - 1, 0 ].max
        # Make sure the task cursor is visible.
        $task_cursor = new_task_cursor
        refresh_taskwin
        $cui.focus.noutrefresh
        $cui.refresh
        handled = true
      end
    elsif event.ch == Curses::Key::PPAGE
      if $selectable_tasks.size > 0
        # Move task cursor to top of current page, or if already there, move
        # one page ($cui.focus.pad.height - 1) up.
        if $task_cursor <= $cui.focus.pad_y
          new_task_cursor = [ $task_cursor - ($cui.focus.pad.height - 1), 0 ].max
        else
          new_task_cursor = $cui.focus.pad_y
        end
        # Make sure the task cursor is visible.
        $task_cursor = new_task_cursor
        refresh_taskwin
        $cui.focus.noutrefresh
        $cui.refresh
        handled = true
      end
    elsif event.ch == Curses::Key::NPAGE
      if $selectable_tasks.size > 0
        # Move task cursor to bottom of current page, or if already there, move
        # one page ($cui.focus.pad.height - 1) down.
        if $task_cursor >= ($cui.focus.pad_y + $cui.focus.pad.height - 1)
          new_task_cursor = [ $task_cursor + ($cui.focus.pad.height - 1),
                              $selectable_tasks.size - 1 ].min
        else
          new_task_cursor = $cui.focus.pad_y + $cui.focus.pad.height - 1
        end
        # Make sure the task cursor is visible.
        $task_cursor = new_task_cursor
        refresh_taskwin
        $cui.focus.noutrefresh
        $cui.refresh
        handled = true
      end
    elsif event.ch == Curses::Key::HOME
      new_task_cursor = 0
      $cui.focus.pad_x = 0
      $cui.focus.pad_y = 0
      refresh_task_cursor $task_cursor, new_task_cursor
      $task_cursor = new_task_cursor
      $cui.focus.noutrefresh
      $cui.refresh
      handled = true
    elsif event.ch == Curses::Key::END
      new_task_cursor = $cui.focus.text.size - 1
      $cui.focus.pad_y = $cui.focus.text.size
      refresh_task_cursor $task_cursor, new_task_cursor
      $task_cursor = new_task_cursor
      $cui.focus.noutrefresh
      $cui.refresh
      handled = true
    elsif event.ch == ' ' or event.ch.to_i == 10
      if $selectable_tasks.size > 0 and $activity_mode.nil?
        # Toggle selection of task under task cursor.
        unless $task_cursor.nil?
          cursor_task = $selectable_tasks[$task_cursor]
          if $selected_tasks.include? cursor_task
            $selected_tasks.delete cursor_task
          else
            $selected_tasks.add cursor_task if cursor_task.startable?
          end
          refresh_taskwin
          $cui.refresh
          handled = true
        end
      end
    elsif event.ch == '-' or event.ch == Curses::Key::BACKSPACE
      if $selectable_tasks.size > 0 and $activity_mode.nil?
        # Deselect task under task cursor.
        unless $task_cursor.nil?
          cursor_task = $selectable_tasks[$task_cursor]
          $selected_tasks.delete cursor_task
          refresh_taskwin
          $cui.refresh
          handled = true
        end
      end
    elsif event.ch == '+'
      if $selectable_tasks.size > 0 and $activity_mode.nil?
        # Select task under task cursor.
        unless $task_cursor.nil?
          cursor_task = $selectable_tasks[$task_cursor]
          $selected_tasks.add cursor_task if cursor_task.startable?
          refresh_taskwin
          $cui.refresh
          handled = true
        end
      end
    elsif event.ch == 't'
      if $selectable_tasks.size > 0 and $activity_mode.nil?
        # Select all tasks of the same type as the one under the task cursor.
        unless $task_cursor.nil?
          cursor_task = $selectable_tasks[$task_cursor]
          type = cursor_task.type
          $selected_tasks.merge $selectable_tasks.select { |t| t.type == type and t.startable? }
          refresh_taskwin
          $cui.refresh
          handled = true
        end
      end
    elsif event.ch == 'a'
      if $selectable_tasks.size > 0 and $activity_mode.nil?
        # Select all tasks.
        $selected_tasks = $selectable_tasks.select { |t| t.startable? }.to_set
        refresh_taskwin
        $cui.refresh
        handled = true
      end
    elsif event.ch == '0'
      if $selectable_tasks.size > 0 and $activity_mode.nil?
        # Deselect all tasks.
        $selected_tasks = Set.new
        refresh_taskwin
        $cui.refresh
        handled = true
      end
    elsif event.ch == 'r'
      if $activity_mode.nil?
        debug_outputs "Pressed 'r' key."
        # Refresh the selectable tasks.
        $activity_mode = :refresh_tasks
        handled = true
      end
    elsif event.ch == 'G'
      if $selectable_tasks.size > 0 and $activity_mode.nil?
        # Perform selected tasks.
        $activity_mode = :perform_selected_tasks
        handled = true
      end
    elsif event.ch == 'm'
      if $selectable_tasks.size > 0 and $activity_mode.nil?
        # Mark selected tasks manually completed.
        $activity_mode = :mark_selected_tasks_complete
        handled = true
      end
    elsif event.ch == 's'
      $show_all_tasks = !$show_all_tasks
      refresh_selectable_tasks
      refresh_status
      refresh_taskwin
      $cui.refresh
      handled = true
    elsif event.ch == 'M'
      # Hack to mark the currently-highlighted task started.
      cursor_task = $selectable_tasks[$task_cursor]
      cursor_task.mark_started
      complete_task cursor_task
      check_windows
      perform_trivial_tasks
      start_startable_timers
      refresh_selectable_tasks
      refresh_status
      refresh_taskwin
      $cui.refresh
      handled = true
    elsif event.ch == '?'
      outputs "Checking ..."
      if $tasklist.find_cycles
        outputs "Cyclic dependency found."
      end
      outputs $tasklist.status
      handled = true
    elsif event.ch == 'd'
      unless $task_cursor.nil?
        output_task_deps $selectable_tasks[$task_cursor]
      end
      handled = true
    elsif event.ch == 'o'
      unless $task_cursor.nil?
        outputs $selectable_tasks[$task_cursor].to_s
        handled = true
      end
    end
  end

  # Generic keystroke effects -- these are the ones that happen no matter what
  # window has the keyboard focus, unless we've already set 'handled' to true.
  unless handled
    if event.ch == 'q'
      debug_outputs "Pressed 'q' key."
      $activity_mode = :exit_activity_loop
#      $activity_loop_done = true
#      $cui.exit_event_loop
    elsif event.ch == 'e' or event.ch == 'x'
      $activity_mode = :exit_activity_loop_and_save
#      $activity_loop_done = true
#      $cui.exit_event_loop
#      save_and_exit
    elsif event.ch == Curses::Key::DOWN
      $cui.focus.pad_y += 1
      $cui.focus.noutrefresh
      $cui.refresh
    elsif event.ch == Curses::Key::UP
      $cui.focus.pad_y -= 1
      $cui.focus.noutrefresh
      $cui.refresh
    elsif event.ch == Curses::Key::RIGHT
      $cui.focus.pad_x += 1
      $cui.focus.noutrefresh
      $cui.refresh
    elsif event.ch == Curses::Key::LEFT
      $cui.focus.pad_x -= 1
      $cui.focus.noutrefresh
      $cui.refresh
    elsif event.ch == Curses::Key::NPAGE
      $cui.focus.pad_y += 10
      $cui.focus.noutrefresh
      $cui.refresh
    elsif event.ch == Curses::Key::PPAGE
      $cui.focus.pad_y -= 10
      $cui.focus.noutrefresh
      $cui.refresh
    elsif event.ch == Curses::Key::HOME
      $cui.focus.pad_x = 0
      $cui.focus.pad_y = 0
      $cui.focus.noutrefresh
      $cui.refresh
    elsif event.ch == Curses::Key::END
      $cui.focus.pad_y = $cui.focus.text.size
      $cui.focus.noutrefresh
      $cui.refresh
    elsif event.ch.to_i == 9
      windex = $window_tab_order.index $cui.focus
      if windex.nil?
        windex = 0
      else
        windex = (windex + 1) % $window_tab_order.size
      end
      $cui.focus = $window_tab_order[windex]
      $cui.focus.noutrefresh
      $cui.refresh
    elsif event.ch.to_i == 12
      $cui.refresh_all
    elsif event.ch == '`'
      dialog_ask_2 "This is a test dialog.", { 'o' => '[o]k' }
    end
  end
end

def handle_focus_in event
  change_info_window
  $cui.refresh
end

def handle_mouse event
  # A mouse click event not handled by the UI has occurred. Do whatever is
  # necessary.

  # Right now the only thing that has meaning is a click on the task
  # list. Obviously we'd change this if that were to change.
  return false unless event.sender == $taskwin

  # First, find out if it's on a line with a task on it (as opposed to a blank
  # line); if not, do nothing.
  row = event.y - $taskwin.pad.abs_y + $taskwin.pad_y
  return false if row >= $taskwin.text.size

  # If it's not in the row designated by $task_cursor, move the task cursor to
  # that row. If it's already in that row, discriminate further.
  if row == $task_cursor
    # If it's in the leftmost column, toggle the select box.
    col = event.x - $taskwin.pad.abs_x
    if col == 0
      if $selected_tasks.include? $selectable_tasks[$task_cursor]
        $selected_tasks.delete $selectable_tasks[$task_cursor]
      else
        $selected_tasks.add $selectable_tasks[$task_cursor]
      end
      refresh_taskwin
      $cui.refresh
      return true
    end
  else
    # Otherwise, highlight that event (move the task cursor to it).
    refresh_task_cursor $task_cursor, row
    $task_cursor = row
    $cui.refresh
    return true
  end

  outputs "#{event.sender.class} '#{event.sender.name}': MouseEvent #{event.bstate} #{event.x} #{event.y}"
  return false
end

def handle_debug event
  # Just push the debug messages onto the $debug_messages array for later
  # printing.

  debug_push "#{event.sender.class} '#{event.sender.name}': #{event.msg}"
end

def handle_refresh event
  # Mostly for debugging, handle RefreshEvents.

  debug_push "#{event.sender.class} '#{event.sender.name}' received RefreshEvent"
end

def main
  $cui.event_loop
end

def fin
  # Tasks to do just before exiting.
  $cui.refresh_all
  $cui.nl
  $cui.echo
  $cui.nocbreak
  $cui.close
  # Since curses makes it impossible to print regular debug messages, push them
  # all to $debug_messages and print them here at the end after curses has
  # relinquished control of the screen.
  if $debug_messages.size > 0
    puts "Debug messages:"
    $debug_messages.each do |msg|
      puts msg
    end
  end
  write_dns_cache
end

###############################################################################
# Main Program
###############################################################################

init
main
fin

# Delete the savefile if it existed. This is here so that the file will still
# exist to be inspected if the script exits early.
File.unlink $savefile if File.exist? $savefile

# PROBLEMS
