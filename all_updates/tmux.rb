module TmuxUtils
  def TmuxUtils::installed?
    # Class method: Determine whether tmux is installed. On an RHEL system,
    # this means looking for the tmux RPM.
    return (system 'rpm -q tmux >&/dev/null')
  end

  def TmuxUtils::running?
    # Class method: Determine whether tmux is running.
    return (system 'tmux ls >&/dev/null')
  end

  def TmuxUtils::in_session?
    # Class method: Determine whether we are currently in a tmux session
    # already.
    return false unless TmuxUtils::running?
    return ENV.key? 'TMUX'
  end

  def TmuxUtils::collect_output cmd, keys, prefix
    output_format = keys.map { |k| "\#{#{prefix}#{k}}" }.join '=*=*='
    output_lines = `tmux #{cmd} -F '#{output_format}'`.split "\n"
    output_arrays = output_lines.map { |line| line.split '=*=*=' }
    output_hashes = []
    output_arrays.each do |arr|
      output_hashes.push (keys.zip arr).to_h
    end
    return output_hashes
  end

  def TmuxUtils::all_window_ids session = nil
    session_arg = ''
    if session == nil
      session_arg = ' -a'
    elsif session == Tmux::CurrentSession
      session_arg = ''
    else
      session_arg = " -t '#{session}'"
    end
    return `tmux list-windows#{session_arg} -F '\#{window_id}'`.split "\n"
  end
end

class Tmux
  # Trying to build in some tmux support. Tmux supports objects called clients,
  # sessions, windows, and panes. They're related like this:
  #
  # Clients: A terminal is either running one tmux client, or it isn't (a
  # terminal runs zero or one tmux clients). A tmux client is attached to zero
  # or one tmux sessions. Zero or more clients can be attached to the same tmux
  # session.
  #
  # Sessions: A given tmux client can be attached to zero or one sessions, and
  # zero or more clients can be attached to a session. A session contains at
  # least one tmux window.

  # be running at least one tmux client. A client will be connected to a
  # session. There will be at least one session, but a client can only be
  # connected to one session at any given time. A session will contain at least
  # one window, but may contain more than one. Each window will contain at
  # least one pane, but may contain more than one.

  include TmuxUtils

  class CurrentSessionClass
  end

  CurrentSession = CurrentSessionClass.new

  class Session
    # A tmux session runs on a tmux server, which can have zero or more
    # sessions in existence at any given time. A session can have zero or more
    # clients connected to it. A session has one or more windows within it, one
    # of which is designated the current window and one of which is the
    # previous window. A session has an ID that is a string consisting of $
    # followed by a decimal integer.

    # Session attributes:

    # session_alerts                  List of window indexes with alerts
    # session_attached                Number of clients session is attached to
    # session_activity                Integer time of session last activity
    # session_created                 Integer time session created
    # session_last_attached           Integer time session last attached
    # session_group                   Number of session group
    # session_grouped                 1 if session in a group
    # session_height                  Height of session
    # session_id                      Unique session ID
    # session_many_attached           1 if multiple clients attached
    # session_name           #S       Name of session
    # session_width                   Width of session
    # session_windows                 Number of windows in session

    attr_reader :alerts, :attached, :activity, :created, :last_attached,
                :group, :grouped, :height, :id, :many_attached, :name, :width,
                :windows

    def initialize arg = nil
      # With no argument or a hash argument, creates a new session. With an
      # argument, grabs the attributes of a session with the given ID.
      return nil unless TmuxUtils::in_session?
      if arg.kind_of? String
        session_id = arg
      elsif arg.kind_of? CurrentSessionClass
        session_id  = Session.current_session_id
      elsif arg.nil? or arg.kind_of? Hash
        args = []
        post = ''
        if arg.kind_of? Hash
          if arg.key? :detach
            args.push '-d'
          end
          if arg.key? :start_directory
            args.push "-a #{arg[:start_directory]}"
          end
          if arg.key? :window_name
            args.push "-n #{arg[:window_name]}"
          end
          if arg.key? :session_name
            args.push "-s #{arg[:session_name]}"
          end
          if arg.key? :target_session
            args.push "-t #{arg[:target_session]}"
          end
          if arg.key? :width
            args.push "-x #{arg[:width]}"
          end
          if arg.key? :height
            args.push "-y #{arg[:height]}"
          end
          if arg.key? :shell_command
            args.push arg[:shell_command]
          end
          if arg.key? :after_command
            post = "; #{arg[:after_command]}"
          end
        end
        output = `tmux new-session -P -F '\#{session_id}' #{args.join ' '}#{post}`
        session_id = output.strip
        raise RuntimeError.new "No session created" if session_id.empty?
      end
      @id = session_id
      self.update
    end

    def update
      session_id = @id
      sessions = Session.attributes.select { |s| s['id'] == session_id }
      raise RuntimeError.new "No such tmux session '#{session_id}'" unless sessions.size > 0
      raise RuntimeError.new "More than one tmux session with ID '#{session_id}'" unless sessions.size < 2
      sessions.first.each do |key, value|
        self.instance_variable_set "@#{key}".to_sym, value
      end
    end

    def current?
      return @id == Session.current_session_id
    end

    def name= newname
      system "tmux rename-session -t '#{@id}' #{newname}"
      @name = newname
    end

    def Session.current
      return Session.new Session.current_session_id
    end

    def Session.current_session_id
      # Returns the ID of the current session.
      return (`tmux list-windows -F '\#{session_id}'`.split "\n").first
    end

    def Session.attributes
      # Returns an array of all sessions' attributes.

      keys = %w(alerts attached activity created last_attached group grouped
                height id many_attached name width windows)

      return TmuxUtils::collect_output 'list-sessions', keys, 'session_'
    end

    def new_window arg = {}
      # Creates a new window within the given session.
      return Tmux::Window.new :detach => arg[:detach],
                              :start_directory => arg[:start_directory],
                              :window_name => arg[:window_name],
                              :target_window => "#{self.id}:",
                              :shell_command => arg[:shell_command]
    end
  end

  class CurrentWindowClass
  end

  CurrentWindow = CurrentWindowClass.new

  class Window
    # A tmux window exists inside at least one session. A window can be part of
    # more than one session. For any session there is a window designated the
    # current window, and another designated the previous window. A window has
    # at least one pane. and for any window there is a pane that is designated
    # the current pane. A window will have an ID, a string consisting of @
    # followed by a decimal integer.

    # Window attributes:

    # window_activity                 Integer time of window last activity
    # window_active                   1 if window active
    # window_bell_flag                1 if window has bell
    # window_find_matches             Matched data from the find-window
    # window_flags           #F       Window flags
    # window_height                   Height of window
    # window_id                       Unique window ID
    # window_index           #I       Index of window
    # window_last_flag                1 if window is the last used
    # window_layout                   Window layout description, ignoring zoomed window panes
    # window_linked                   1 if window is linked across sessions
    # window_name            #W       Name of window
    # window_panes                    Number of panes in window
    # window_silence_flag             1 if window has silence alert
    # window_visible_layout           Window layout description, respecting zoomed window panes
    # window_width                    Width of window
    # window_zoomed_flag              1 if window is zoomed

    attr_reader :activity, :active, :bell_flag, :find_matches, :flags, :height,
                :id, :index, :last_flag, :layout, :linked, :name, :panes,
                :silence_flag, :visible_layout, :width, :zoomed_flag

    def initialize arg = nil
      if arg.kind_of? String
        window_id = arg
      elsif window_id.kind_of? CurrentWindowClass
        window_id = Window.current_window_id
      elsif arg.nil? or arg.kind_of? Hash
        args = []
        if arg.kind_of? Hash
          if arg.key? :detach
            args.push '-d'
          end
          if arg.key? :start_directory and !arg[:start_directory].nil? and !arg[:start_directory].empty?
            args.push (sprintf '-c "%s"', arg[:start_directory])
          end
          if arg.key? :window_name
            args.push (sprintf '-n "%s"', arg[:window_name])
          end
          if arg.key? :target_window
            args.push (sprintf '-t \'%s\'', arg[:target_window])
          end
          if arg.key? :shell_command
            args.push (sprintf '"%s"', arg[:shell_command])
          end
        end
        command = sprintf 'tmux new-window -P -F \'#{window_id}\' %s',
                          (args.join ' ')
        output = `#{command}`
        window_id = output.strip
        raise RuntimeError.new "No window created (cmd = #{command})" if window_id.empty?
      end
      @id = window_id
      # It is possible that the command has already completed and the window
      # has already closed, in which case this update will cause an
      # exception. Test whether it's open first.
      self.update if self.open?
    end

    def update
      window_id = @id
      windows = (Window.attributes CurrentSession).select { |w| w['id'] == window_id }
      raise RuntimeError.new "No such tmux window '#{window_id}'" unless windows.size > 0
      raise RuntimeError.new "More than one tmux window with ID '#{window_id}'" unless windows.size < 2
      windows.first.each do |key, value|
        self.instance_variable_set "@#{key}".to_sym, value
      end
    end

    def select
      `tmux select-window -t '#{self.id}'`
    end

    def current?
      return @id == Window.current_window_id
    end

    def open?
      # Since there's nothing preventing a user from closing a tmux window that
      # we have an object for, this will check to see whether the related
      # window still exists. Returns true if so and false if not.
      window_id = @id
      windows = (Window.attributes).select { |w| w['id'] == window_id }
      raise RuntimeError.new "More than one tmux window with ID '#{window_id}'" unless windows.size < 2
      return true if windows.size == 1
      return false
    end

    def Window.current
      return Window.new Window.current_window_id
    end

    def Window.current_window_id
      return (`tmux list-panes -F '\#{window_id}'`.split "\n").first
    end

    def Window.attributes target = nil
      # With no argument, returns an array of all windows' attributes. If the
      # argument is a Tmux::Session, returns an array of all of that session's
      # windows' attributes. If the argument is Tmux::CURRENT_SESSION, returns
      # an array of all of the current session's windows' attributes.

      keys = %w(activity active bell_flag find_matches flags height id index
                last_flag layout linked name panes silence_flag visible_layout
                width zoomed_flag)

      args = ''
      if target.kind_of? Tmux::CurrentSessionClass
        args = ''
      elsif target.kind_of? Tmux::Session
        args = "-t #{target.id}"
      else
        args = '-a'
      end
      return TmuxUtils::collect_output "list-windows #{args}", keys, 'window_'
    end
  end

  class CurrentPaneClass
  end

  CurrentPane = CurrentPaneClass.new

  class Pane
    # A tmux pane exists within a tmux window, which must have at least one
    # pane. A window has a current pane. A pane has a ptty associated with
    # it. A pane has an ID, a string consisting of % followed by a decimal
    # integer.

    # Pane attributes:

    # pane_active                     1 if active pane
    # pane_bottom                     Bottom of pane
    # pane_current_command            Current command if available
    # pane_current_path               Current path if available
    # pane_dead                       1 if pane is dead
    # pane_dead_status                Exit status of process in dead pane
    # pane_height                     Height of pane
    # pane_id                #D       Unique pane ID
    # pane_in_mode                    If pane is in a mode
    # pane_input_off                  If input to pane is disabled
    # pane_index             #P       Index of pane
    # pane_left                       Left of pane
    # pane_pid                        PID of first process in pane
    # pane_right                      Right of pane
    # pane_start_command              Command pane started with
    # pane_synchronized               If pane is synchronized
    # pane_tabs                       Pane tab positions
    # pane_title             #T       Title of pane
    # pane_top                        Top of pane
    # pane_tty                        Pseudo terminal of pane
    # pane_width                      Width of pane

    attr_reader :active, :bottom, :current_command, :current_path, :dead,
                :dead_status, :height, :id, :in_mode, :input_off, :index,
                :left, :pid, :right, :start_command, :synchronized, :tabs,
                :title, :top, :tty, :width

    def initialize arg = nil
      # If this is called without an argument (pane_id == nil), assume that
      # means to create a new pane within the current window. If called with an
      # argument, create a Tmux::Pane object referring to the existing pane
      # with the given pane_id. If pane_id is "current", returns a special
      # Tmux::Pane that refers to the current pane.
      if arg.kind_of? String
        pane_id = arg
      elsif arg.kind_of? CurrentPaneClass
        pane_id = Pane.current_pane_id
      elsif arg.nil? or arg.kind_of? Hash
        args = []
        if arg.kind_of? Hash
          if arg.key? :detach
            args.push '-d'
          end
          if arg.key? :vertical
            args.push '-v'
          elsif arg.key? :horizontal
            args.push '-h'
          end
          if arg.key? :before
            args.push '-b'
          end
          if arg.key? :start_directory
            args.push "-c #{arg[:start-directory]}"
          end
          if arg.key? :size
            if arg[:size].end_with? '%'
              args.push "-p #{arg[:size].sub(/%$/, '')}"
            else
              args.push "-l #{arg[:size]}"
            end
          end
          if arg.key? :target_pane
            args.push "-t #{arg[:target-pane]}"
          end
          if arg.key? :shell_command
            args.push arg[:shell_command]
          end
        end
        output = `tmux split-window -d -P -F '\#{pane_id}' #{args.join ' '}`
        pane_id = output.strip
      end
      @id = pane_id
      self.update
    end

    def update
      pane_id = @id
      panes = (Pane.attributes CurrentWindow).select { |p| p['id'] == pane_id }
      raise RuntimeError.new "No such tmux pane '#{pane_id}'" unless panes.size > 0
      raise RuntimeError.new "More than one tmux pane with ID '#{pane_id}'" unless panes.size < 2
      panes.first.each do |key, value|
        self.instance_variable_set "@#{key}".to_sym, value
      end
    end

    def current?
      return @id == Pane.current_pane_id
    end

    def Pane.current
      return Pane.new Pane.current_pane_id
    end

    def Pane.current_pane_id
      # Returns the current Tmux::Pane, or nil if we aren't in one. The
      # TMUX_PANE environment variable normally contains the tmux pane_id.
      return nil unless ENV.key? 'TMUX_PANE'
      return ENV['TMUX_PANE']
    end

    def Pane.attributes target = nil
      # With no argument, returns an array of all panes' attributes. If the
      # argument is a Tmux::Session or Tmux::Window, returns an array of all of
      # that session's or window's panes' attributes. If the argument is
      # Tmux::CurrentSession or Tmux::CurrentWindow, returns an array of the
      # current session's or window's panes' attributes.

      keys = %w(active bottom current_command current_path dead dead_status
                height id in_mode input_off index left pid right start_command
                synchronized tabs title top tty width)

      args = ''
      if target.kind_of? Tmux::CurrentSessionClass
        args = '-s'
      elsif target.kind_of? Tmux::Session
        args = "-s -t #{target.id}"
      elsif target.kind_of? Tmux::CurrentWindowClass
        args = ''
      elsif target.kind_of? Tmux::Window
        args = "-t #{target.id}"
      else
        args = '-a'
      end
      return TmuxUtils::collect_output "list-panes #{args}", keys, 'pane_'
    end
  end

  class CurrentClientClass
  end

  CurrentClient = CurrentClientClass.new

  class Client
    # A tmux client is attached to a terminal and may (or may not) be connected
    # to a (only one) tmux server. If connected to a server, it may (or may
    # not) be connected to a (only one) tmux session.

    # client_activity                 Integer time client last had activity
    # client_created                  Integer time client created
    # client_control_mode             1 if client is in control mode
    # client_height                   Height of client
    # client_key_table                Current key table
    # client_last_session             Name of the client's last session
    # client_pid                      PID of client process
    # client_prefix                   1 if prefix key has been pressed
    # client_readonly                 1 if client is readonly
    # client_session                  Name of the client's session
    # client_termname                 Terminal name of client
    # client_tty                      Pseudo terminal of client
    # client_utf8                     1 if client supports utf8
    # client_width                    Width of client

    def initialize client_pid
      if client_pid.kind_of? CurrentClientClass
        @pid = 'CURRENT'
      end
    end

    def Client.attributes target = nil
      # With no arguments, returns an array of all clients' attributes. If the
      # argument is a Tmux::Session, returns an array of the attributes of all
      # clients connected to the given session. If the argument is
      # Tmux::CurrentSession, returns an array of the current session's
      # clients' attributes.

      keys = %w(activity created control_mode height key_table last_session pid
                prefix readonly session termname tty utf8 width)

      args = ''
      if target.kind_of? Tmux::CurrentSessionClass
        args = "-t #{Tmux.current_session.id}"
      elsif target.kind_of? Tmux::Session
        args = "-t #{target.id}"
      end
      return TmuxUtils::collect_output "list-clients #{args}", keys, 'client_'
    end
  end

  def initialize
  end

  def current_pane
    return Pane.current
  end
end

