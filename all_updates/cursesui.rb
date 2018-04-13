# coding: utf-8
require 'curses'
require 'forwardable'
require 'securerandom'

class Curses::Window
  # Additional methods for Curses::Windows objects.

  # Default border character if the caller specifies no border, or uses preset
  # :base.
  DEFAULT_BORDER_BASE = '*'

  def border arg = {}
    # Because the Curses class implements curses' box() function but not its
    # border() function, I've written my own, and this one is better. Draws a
    # border around the inside of the window. If there are no arguments, draws
    # a :single border (see below). Otherwise, call with a hash that has these
    # symbols as keys:
    #
    # :preset -- draws preset borders. Use :single, :double, or several others.
    # :base -- character to use for any unspecified characters. If this is the
    # only key, draws entire border with this character.
    # :vert -- character to use for vertical lines on left and right.
    # :horiz -- character to use for horizontal lines on top and bottom.
    # :v, :h -- abbreviations for :vert and :horiz.
    # :top -- character to use for top border.
    # :bottom -- character to use for bottom border.
    # :left -- character to use for left border.
    # :right -- character to use for right border.
    # :t, :b, :l, :r -- abbreviations for sides.
    # :top_left, :top_right, :bottom_left, :bottom_right -- corner characters.
    # :tl, :tr, :bl, :br -- abbreviations for corners.

    # No arguments -- default case
    if arg.empty?
      arg = { :preset => :single }
    end

    # Set a default base character.
    base = DEFAULT_BORDER_BASE
    # Deal with :base argument that changes this base character. Must be a
    # String of size 1 (can be a single wide character, of course).
    if arg.key? :base
      raise RuntimeError "Value for :base is not a String (#{arg[:base].class})" unless arg[:base].kind_of? String
      base = arg[:base][0]
    end
    b = {
      :t => base,
      :b => base,
      :l => base,
      :r => base,
      :tl => base,
      :tr => base,
      :bl => base,
      :br => base,
    }

    # See if a :preset is selected.
    if arg.key? :preset
      if arg[:preset] == :blank
        b[:t] = " "
        b[:b] = " "
        b[:l] = " "
        b[:r] = " "
        b[:tl] = " "
        b[:tr] = " "
        b[:bl] = " "
        b[:br] = " "
      elsif arg[:preset] == :single
        b[:t] = "\u2500"
        b[:b] = "\u2500"
        b[:l] = "\u2502"
        b[:r] = "\u2502"
        b[:tl] = "\u250c"
        b[:tr] = "\u2510"
        b[:bl] = "\u2514"
        b[:br] = "\u2518"
      elsif arg[:preset] == :heavy
        b[:t] = "\u2501"
        b[:b] = "\u2501"
        b[:l] = "\u2503"
        b[:r] = "\u2503"
        b[:tl] = "\u250f"
        b[:tr] = "\u2513"
        b[:bl] = "\u2517"
        b[:br] = "\u251b"
      elsif arg[:preset] == :double
        b[:t] = "\u2550"
        b[:b] = "\u2550"
        b[:l] = "\u2551"
        b[:r] = "\u2551"
        b[:tl] = "\u2554"
        b[:tr] = "\u2557"
        b[:bl] = "\u255a"
        b[:br] = "\u255d"
      elsif arg[:preset] == :dashed2
        b[:t] = "\u254c"
        b[:b] = "\u254c"
        b[:l] = "\u254e"
        b[:r] = "\u254e"
        b[:tl] = "\u250c"
        b[:tr] = "\u2510"
        b[:bl] = "\u2514"
        b[:br] = "\u2518"
      elsif arg[:preset] == :dashed3
        b[:t] = "\u2504"
        b[:b] = "\u2504"
        b[:l] = "\u2506"
        b[:r] = "\u2506"
        b[:tl] = "\u250c"
        b[:tr] = "\u2510"
        b[:bl] = "\u2514"
        b[:br] = "\u2518"
      elsif arg[:preset] == :dashed4
        b[:t] = "\u2509"
        b[:b] = "\u2509"
        b[:l] = "\u250a"
        b[:r] = "\u250a"
        b[:tl] = "\u250c"
        b[:tr] = "\u2510"
        b[:bl] = "\u2514"
        b[:br] = "\u2518"
      elsif arg[:preset] == :dashed2_heavy
        b[:t] = "\u254d"
        b[:b] = "\u254d"
        b[:l] = "\u254f"
        b[:r] = "\u254f"
        b[:tl] = "\u250f"
        b[:tr] = "\u2513"
        b[:bl] = "\u2517"
        b[:br] = "\u251b"
      elsif arg[:preset] == :dashed3_heavy
        b[:t] = "\u2505"
        b[:b] = "\u2505"
        b[:l] = "\u2507"
        b[:r] = "\u2507"
        b[:tl] = "\u250f"
        b[:tr] = "\u2513"
        b[:bl] = "\u2517"
        b[:br] = "\u251b"
      elsif arg[:preset] == :dashed4_heavy
        b[:t] = "\u2509"
        b[:b] = "\u2509"
        b[:l] = "\u250b"
        b[:r] = "\u250b"
        b[:tl] = "\u250f"
        b[:tr] = "\u2513"
        b[:bl] = "\u2517"
        b[:br] = "\u251b"
      elsif arg[:preset] == :dotted
        b[:t] = "\u00b7"
        b[:b] = "\u00b7"
        b[:l] = "\u205a"
        b[:r] = "\u205a"
        b[:tl] = "\u00b7"
        b[:tr] = "\u00b7"
        b[:bl] = "\u00b7"
        b[:br] = "\u00b7"
      else
        raise RuntimeError "Value for :preset is not a recognized symbol (:#{arg[:preset]})"
      end
    end

    # The :vert and :horiz keys are first because it's possible to specify them
    # then overwrite one or the other value -- one could specify :horiz and
    # then change :bottom, for example.
    [:v, :vert].each do |k|
      # If for some reason both :vert and :v (its abbreviation) are specified,
      # the full spelling overrides the abbreviation. I don't know why someone
      # would do this, but this policy will make things more robust.
      if arg.key? k
        b[:l] = arg[k]
        b[:r] = arg[k]
      end
    end
    [:h, :horiz].each do |k|
      if arg.key? k
        b[:t] = arg[k]
        b[:b] = arg[k]
      end
    end
    [:t, :top].each do |k|
      if arg.key? k
        b[:t] = arg[k]
      end
    end
    [:b, :bottom].each do |k|
      if arg.key? k
        b[:b] = arg[k]
      end
    end
    [:l, :left].each do |k|
      if arg.key? k
        b[:l] = arg[k]
      end
    end
    [:r, :right].each do |k|
      if arg.key? k
        b[:r] = arg[k]
      end
    end
    [:tl, :top_left].each do |k|
      if arg.key? k
        b[:tl] = arg[k]
      end
    end
    [:tr, :top_right].each do |k|
      if arg.key? k
        b[:tr] = arg[k]
      end
    end
    [:bl, :bottom_left].each do |k|
      if arg.key? k
        b[:bl] = arg[k]
      end
    end
    [:br, :bottom_right].each do |k|
      if arg.key? k
        b[:br] = arg[k]
      end
    end

    # Make absolutely sure that each value in b is one character long.
    b.each do |k, v|
      v = v[0] if v.respond_to? :[]
    end

    # Do the actual drawing of the border.
    self.setpos 0, 0
#    raise Exception.new "self.maxx = #{self.maxx}" if self.maxx <= 2
    self.addstr b[:tl] + b[:t]*(self.maxx - 2) + b[:tr]
    row = 1
    (self.maxy - 2).times do
      self.setpos row, 0
      self.addstr b[:l]
      self.setpos row, self.maxx - 1
      self.addstr b[:r]
      row += 1
    end
    self.setpos self.maxy - 1, 0
    self.addstr b[:bl] + b[:b]*(self.maxx - 2) + b[:br]
  end
end

class CUIError < RuntimeError
end

class CUIArgumentError < CUIError
end

class CUIContainmentError < CUIError
end

class Curses::Ui
  # Implement an actual UI in Curses containing standard UI elements and
  # concepts, such as UI objects that contain other UI objects, act in
  # UI-typical ways, etc. Written with the Perl module Curses::UI in mind, but
  # not a port of that.

  attr_reader :refresh_stack

  def initialize
    Curses.init_screen
    Curses.start_color if Curses.has_colors?
    Curses.mousemask Curses::BUTTON1_CLICKED
    @focus = STDSCR
    @modal = false
    @event_loop_callback = nil
    @event_loop_done = false
    @waiting = false
    @event_registry = EventRegistry.new :name => 'Event Registry',
                                        :cui => self
    @event_queue = EventQueue.new :name => 'Event Queue',
                                  :cui => self
    @refresh_stack = RefreshStack.new :name => 'Refresh Stack',
                                      :cui => self
  end

  def refresh_stack_push obj
    return @refresh_stack.push obj
  end

  def refresh_stack_pop
    return @refresh_stack.pop
  end

  def new_cp arg = {}
    arg[:cui] = self
    return Curses::Ui::CP.new arg
  end

  def new_event arg = {}
    arg[:cui] = self
    return Curses::Ui::Event.new arg
  end

  def new_window arg = {}
    arg[:cui] = self
    window = Curses::Ui::Window.new arg
    return window
  end

  def new_bordered_window arg = {}
    arg[:cui] = self
    window = Curses::Ui::BorderedWindow.new arg
    return window
  end

  def new_scroll_window arg = {}
    arg[:cui] = self
    sw = Curses::Ui::ScrollWindow.new arg
    raise RuntimeError.new "Newly created ScrollWindow is nil" if sw.nil?
    sw.hbar.container = sw
    raise CUIContainmentError.new "#{sw.hbar.class} '#{sw.hbar.name}' has nil container" if sw.hbar.container.nil?
    return sw
  end

  def new_pad arg = {}
    arg[:cui] = self
    pad = Curses::Ui::Pad.new arg
    return pad
  end

  def new_textviewer arg = {}
    arg[:cui] = self
    window = Curses::Ui::TextViewer.new arg
    return window
  end

  def new_vertical_scroll_bar arg = {}
    arg[:cui] = self
    vbar = Curses::Ui::VerticalScrollBar.new arg
    return vbar
  end

  def new_horizontal_scroll_bar arg = {}
    arg[:cui] = self
    hbar = Curses::Ui::HorizontalScrollBar.new arg
    return hbar
  end

  def new_hbox arg = {}
    arg[:cui] = self
    return Curses::Ui::HBox.new arg
  end

  def new_vbox arg = {}
    arg[:cui] = self
    return Curses::Ui::VBox.new arg
  end

  def new_dialog arg = {}
    arg[:cui] = self
    return Curses::Ui::Dialog.new arg
  end

  def new_button arg = {}
    arg[:cui] = self
    return Curses::Ui::Button.new arg
  end

  def cbreak
    return Curses.cbreak
  end

  def nocbreak
    return Curses.nocbreak
  end

  def nl
    return Curses.nl
  end

  def nonl
    return Curses.nonl
  end

  def curs_set mode
    return Curses.curs_set mode
  end

  def echo
    return Curses.echo
  end

  def noecho
    return Curses.noecho
  end

  def cols
    return Curses.cols
  end

  def lines
    return Curses.lines
  end

  def rows
    return Curses.lines
  end

  def refresh_all
    @refresh_stack.noutrefresh
    return Curses.doupdate
  end

  def refresh
    return Curses.doupdate
  end

  def close
    @event_queue.handle @event_registry
    return Curses.close_screen
  end

  def print_event_queue
    @event_queue.print
  end

  def focus= obj
    # Sets the keyboard focus to obj, or to the first @contents object that
    # responds to getch, if this is a ContainerObject or similar. Sets
    # obj.nodelay to the given value (true by default).

    raise CUIArgumentError.new "Keyboard focus set to an object that does not respond to getch" unless obj.respond_to? :getch
    raise CUIArgumentError.new "Attempted to set keyboard focus to an object that cannot be set focusable" unless obj.respond_to? :focusable?
    raise CUIArgumentError.new "Attempted to set keyboard focus to an object that is not set focusable" unless obj.focusable?
    return if obj.respond_to?(:focused) and obj.focused
    @focus.focused = false if @focus.respond_to?(:focused=)
    self.event @focus, FocusOutEvent
    @focus = obj
    self.event @focus, FocusInEvent
    @focus.focused = true if @focus.respond_to?(:focused=)
    # Refresh the window stack as this will likely change the borders.
    self.refresh_all
  end

  def wait
    # Waits for an event loop iteration.
    return if @event_loop_done
    @waiting = true
    loop do
      sleep 0.02
      break unless @waiting
      break if @event_loop_done
    end
  end

  def focus
    # Returns the Curses::Ui object currently set as the keyboard focus.
    return @focus
  end

  def capture_keyboard
    # Sets the @modal flag, which is something you might want to do if you are
    # having something other than the event loop capture keyboard input. When
    # this is set, the event loop stops polling for keys, meaning that code
    # outside these Curses::Ui classes (i.e. your script) gains the privilege
    # and responsibility to capture keystrokes itself.
    @modal = true
  end

  def keyboard_captured?
    # Just returns true if the keyboard is captured and false if not.
    return @modal
  end

  def release_keyboard
    # Clears the @modal flag, enabling the event loop to capture keyboard input
    # once again (the default state).
    @modal = false
  end

  def register_event_handler event_spec, proc
    # Registers the given Proc object as a handler for the given event
    # specifier in the @event_registry, returning the key it was assigned in
    # case you want to unregister it later.
    #
    # An event specifier can either be the actual class constant,
    # Curses::Ui::KeyEvent for example, or it can be the name of the class as a
    # string ('Curses::Ui::KeyEvent'), or the basename of the class
    # ('KeyEvent'), and you can even leave off the 'Event' at the end ('Key').

    return @event_registry.register event_spec, proc
  end

  def unregister_event_handler event_class, key
    # Unregisters the handler with the given key as a handler for events of the
    # given class in the @event_registry. The key is the one returned when you
    # registered the event.
    return @event_registry.unregister event_class, key
  end

  def event sender, event_class, *args
    # Creates an event and pushes it on the @event_queue. The sender should be
    # the actual object that sent the event. The event_class should be the
    # class of event to send. The other arguments will depend on the event
    # class.
    raise "Event sender not a Curses::Ui object (is a #{sender.class})" unless sender.kind_of? Curses::Ui::Object
    raise "Event class not a Class (is a #{event_class.class})" unless event_class.kind_of? Class
    @event_queue.push_event sender, event_class, *args
  end

  def print_event_queue
    @event_queue.print
  end

  def event_loop_callback= proc
    raise CUIArgumentError.new "Argument is not class Proc (is class #{proc.class} instead)" unless proc.kind_of? Proc
    @event_loop_callback = proc
  end

  def event_loop
    @event_loop_done = false
    loop do
      break if @event_loop_done
      unless @modal
        ch = @focus.getch
        unless ch.nil?
          if ch == Curses::KEY_MOUSE
            # If the "key" was actually a mouse event, deal with that.
            m = Curses.getmouse
            unless m.nil?
              # See if there is something that Curses::Ui has to react to, like
              # a clicked button, scroll bar, or background window.
              unless self.handle_mouse m
                # Send a mouse event so other code can register and respond to
                # these.
                self.event(@focus, MouseEvent,
                           :bstate => m.bstate,
                           :x => m.x,
                           :y => m.y)
              end
            end
          else
            # Just a regular key event.
            self.event @focus, KeyEvent, :ch => ch
          end
        end
      end
      @event_queue.handle @event_registry
      @event_loop_callback.call unless @event_loop_callback.nil?
      sleep 0.02
      # If a wait was in progress, end it now.
      @waiting = false
    end
  end

  def handle_mouse m
    # Handle the given mouse event, a Curses::MouseEvent object with attributes
    # bstate, x, and y. Returns true if this method handled the event (that is,
    # if it was something that Curses::Ui needed to react to, like a button
    # click, a click on a scroll bar, etc.) and no MouseEvent needs to be
    # generated. Returns false if this wasn't an event that Curses::Ui needed
    # to see, so a MouseEvent needs to be generated so the calling code can
    # handle it if it wants to.

    raise CUIArgumentError.new "Argument not a Curses::MouseEvent (is #{m.class})" unless m.respond_to? :x and m.respond_to? :y and m.respond_to? :bstate
    # First of all, was this a click?
    if m.bstate & Curses::BUTTON1_CLICKED
      # Was this a click in a background window (that is, one that doesn't have
      # keyboard focus)?
      clicked_obj = nil
      @refresh_stack.reverse_each do |obj|
        next unless obj.respond_to? :focused
        next if obj.focused
        if obj.mouse_within? m
          clicked_obj = obj
          break
        end
      end
      if clicked_obj and clicked_obj.focusable?
        # Bring that background window forward.
        clicked_obj.move_to_top if clicked_obj.respond_to? :move_to_top
        self.focus = clicked_obj
        return true
      end
      # Was this a click in the foreground window?
      if self.focus.mouse_within? m
        # Give the MouseEvent to the keyboard focus object's handle_mouse
        # method if one exists.
        if self.focus.respond_to?(:handle_mouse)
          result = self.focus.handle_mouse m
          # Return true if that returned true -- otherwise, that means it
          # didn't want exclusive rights to that event for some reason (the
          # click wasn't on anything significant, for example), so something
          # else might handle it.
          return true if result
        end
      end
    end
    return false
  end

  def exit_event_loop
    @event_loop_done = true
  end

  def stdscr
    return STDSCR
  end

  module Container
    # Methods common to all objects that can be contained in other objects.

    def abs_x
      # Contained objects sometimes need their absolute screen coordinates
      # relative to Curses.stdscr. Usually their x and y coordinates are
      # relative to their containers, which is convenient except when you need
      # to give coordinates to the underlying Curses methods, which don't work
      # like that and need absolute coordinates. So we have to crawl up the
      # tree of containers adding coordinates as we go until we get to
      # Curses::Ui::STDSCR, the constant Curses::Ui object that wraps
      # Curses.stdscr. If we run into a nil container (either something didn't
      # set its container or it actually set nil as its container), raise an
      # exception.
      total = 0
      obj = self
      loop do
        break if obj.kind_of? RootWindow
        total += obj.x
        raise CUIContainmentError.new "#{obj.class} '#{obj.name}' has nil container" if obj.container.nil?
        obj = obj.container
      end
      return total
    end

    def abs_y
      total = 0
      obj = self
      loop do
        break if obj.kind_of? RootWindow
        total += obj.y
        raise CUIContainmentError.new "#{obj.class} '#{obj.name}' has nil container" if obj.container.nil?
        obj = obj.container
      end
      return total
    end
  end

  class Object
    # Curses::Ui::Object is just a catch-all class for all classes created by
    # Curses::Ui.

    attr_accessor :name, :cui

    def initialize arg = {}
      # There must be a Curses::Ui object, or the class can never call any
      # Curses::Ui instance methods. Of course, this is usually given by the
      # method that created this object, like Curses::Ui#new_window.
      unless arg.key? :cui
        raise CUIArgumentError.new "No Curses::Ui object given"
      end
      @cui = arg[:cui]
      @name = arg[:name] if arg.key? :name
    end

    def to_s
      return "#{self.class} '#{@name}'"
    end
  end

  class Event < Object
    # An event in the Curses::Ui system is a message that an object has put
    # there for other code to look at. Basically all the event loop does is
    # look in the event queue for events and give them to anything that has
    # requested notification if that class of event happens. I expect I'll be
    # subclassing Event so there can be different types of events with
    # different attributes.

    attr_reader :sender

    def initialize arg = {}
      super
      raise CUIArgumentError.new "Event.new called without sender" unless arg.key? :sender
      @sender = arg[:sender]
    end

    def handle registry
      # Calls all handlers for this event's class in the given registry.
      (registry.handlers_for self.class).each do |proc|
        next if proc.nil?
        proc.call self
      end
    end
  end

  class FocusOutEvent < Event
  end

  class FocusInEvent < Event
  end

  class RefreshEvent < Event
  end

  class KeyEvent < Event
    attr_reader :ch

    def initialize arg = {}
      super
      raise CUIArgumentError.new "KeyEvent.new called without key" unless arg.key? :ch
      @ch = arg[:ch]
    end
  end

  class MouseEvent < Event
    attr_reader :bstate, :x, :y

    def initialize arg = {}
      super
      [:bstate, :x, :y].each do |attr|
        if arg.key? attr
          self.instance_variable_set "@#{attr}", arg[attr]
        end
      end
    end
  end

  class EventQueue < Object
    # An event queue just has a list of events that have been pushed into
    # it. Call @queue.push_event to push a new event onto the queue, and call
    # @handle to handle those events using handlers found in an EventRegistry.

    extend Forwardable

    def_delegators :@events, :each, :push, :shift, :size, :length

    attr_accessor :events

    def initialize arg = {}
      super
      @events = []
    end

    def push_event sender, event_class, *args
      # Puts an event onto the event queue.

      arg_hash = Hash[*args]
      arg_hash[:sender] = sender
      arg_hash[:cui] = @cui
      self.push (event_class.new arg_hash)
    end

    def handle registry
      # Handles each event in the queue given the contents of the given event
      # registry.

      loop do
        break if @events.size == 0
        (@events.shift).handle registry
      end
    end

    def print
      self.each do |event|
        puts "#{event.sender.class}#{if event.sender.name; then ' \'#{event.sender.name}\''; end} -> #{event.class}#{if event.respond_to? :msg; ': ' + event.msg; end}"
      end
    end
  end

  class EventRegistry < Object
    # An event registry really just keeps track of the various Procs that are
    # registered as handlers for the various events that occur.

    private

    def eventify event_spec
      # Tries to turn event_spec into a Curses::Ui event class (e.g. 'Key'
      # becomes Curses::Ui::KeyEvent). If this is not possible, returns nil.

      # First off, if event_spec is already a Curses::Ui event class, return
      # it; we're done already.
      if event_spec.kind_of? Class
        if event_spec.to_s.start_with? 'Curses::Ui::' and event_spec.to_s.end_with? 'Event'
          # This means it's already a Curses::Ui event class, so it can be
          # returned as is.
          return event_spec
        else
          # It may be a class, but it's not a Curses::Ui event class, so I
          # don't know what to do with whatever it is.
          return nil
        end
      elsif event_spec.kind_of? String
        # See if we can turn this into an event class. First of all, maybe it's
        # the name of one.
        begin
          # There's no way to test to see whether this will work before trying
          # it; if you try Method.const_get and there's no constant with the
          # given name, you get a NameError exception, so we have to put the
          # attempt within a begin...end and rescue it.
          event_class = Method.const_get event_spec
        rescue NameError => err
          if event_spec.start_with? 'Curses::Ui::' and event_spec.end_with? 'Event'
            # The string showed all the hallmarks of being the name of an event
            # class, but it wasn't one.
            raise RuntimeError.new "event_spec was #{event_spec}"
            return nil
          else
            # Try adding the prefix to the beginning and the suffix on the end
            # if they're not already there.
            event_spec = 'Curses::Ui::' + event_spec unless event_spec.start_with? 'Curses::Ui::'
            event_spec += 'Event' unless event_spec.end_with? 'Event'
            retry
          end
        end
        return event_class
      else
        # I don't know what to do with it if it isn't a Class or a String.
        return nil
      end
    end

    def unique_key event_class
      # Returns a key for @registry[event_class] that is guaranteed not to
      # already exist. This does not guarantee that it doesn't already exist
      # for @registry[some_other_event_class].

      @registry[event_class] = {} unless @registry.key? event_class
      key = nil
      loop do
        key = SecureRandom.hex(10)
        break unless @registry[event_class].key? key
      end
      return key
    end

    public

    def initialize arg = {}
      super
      @registry = Hash.new { |h, k| h[k] = {} }
    end

    def register event_spec, proc
      # Given an event class and a Proc, adds the Proc to the hash of Procs to
      # be called when an event of the given class is encountered. Returns the
      # key in the registry of the entry created. If event_class is not an
      # actual class, tries to fill it out into one.

      event_class = eventify event_spec
      raise CUIArgumentError.new "Unknown event class '#{event_spec}'" if event_class.nil?
      raise CUIArgumentError.new "Not given a Proc (#{proc.class} instead)" unless proc.kind_of? Proc
      new_key = unique_key event_class
#      @registry[event_class] = {} unless @registry.key? event_class and @registry[event_class].respond_to? :[]
      key = unique_key event_class
      @registry[event_class][key] = proc
      return key
    end

    def unregister event_spec, key
      # Unregisters the Proc at the given key in the hash of Procs for the
      # given event type.
      event_class = eventify event_spec
      raise CUIArgumentError.new "Unknown event class '#{event_spec}'" if event_class.nil?
      return nil unless @registry.key? event_class
#      return nil unless @registry[event_class].respond_to? :key? and $registry[event_class].respond_to? :delete
      return nil unless @registry[event_class].key? key
      @registry[event_class].delete key
    end

    def handlers_for event_spec
      # Returns the list of handlers for a given event.

      event_class = eventify event_spec
      raise CUIArgumentError.new "Unknown event class '#{event_spec}'" if event_class.nil?
      return [] unless @registry.key? event_class
      return [] unless @registry[event_class].respond_to? :values
      return @registry[event_class].values
    end

    def to_s
      # Renders the event registry as a string, usually for debugging purposes.
      str = ''
      @registry.keys.sort { |a, b| a.to_s <=> b.to_s }.each do |evclass|
        str += "#{evclass}: #{@registry[evclass].size} registered handlers\n"
      end
      return str
    end
  end

  class RefreshStack < Object
    # There will only be one RefreshStack, and it typically won't be accessed
    # directly, but we have to define it.

    extend Forwardable

    def_delegators :@stack, :each, :pop, :reverse_each

    def initialize arg = {}
      super
      @stack = []
    end

    def push obj
      # Pushes an object onto the top of the stack (it will thus be the last
      # object refreshed). Returns what @stack.push returns, which is the array
      # itself.

      raise CUIArgumentError.new "Tried to push an undisplayable object onto a RefreshStack" unless obj.kind_of? DisplayableObject
      raise CUIArgumentError.new "Tried to push an object onto a RefreshStack that is already in that RefreshStack" if @stack.include? obj
      return @stack.push obj
    end

    def pop
      # Removes and returns the top object from the stack (it will thus no
      # longer be in the window stack and will not be refreshed when
      # Curses::Ui#refresh is called).

      return @stack.pop
    end

    def remove obj
      # Removes obj from the window stack, if obj is in it. Returns nil if
      # nothing was deleted; otherwise, returns obj.
      return @stack.delete obj
    end

    def move_up obj
      # Assuming obj is found in @stack and is not the last item in @stack,
      # swaps obj's position with that of the next item in @stack.

      raise CUIArgumentError.new "Given object is not in the RefreshStack" unless @stack.include? obj
      return if obj == @stack.last
      ind = @stack.index obj
      (@stack[ind + 1], @stack[ind]) = @stack[ind..(ind + 1)]
    end

    def move_down obj
      # Assuming obj is found in @stack and is not the first item in @stack,
      # swaps obj's position with that of the previous item in @stack.

      raise CUIArgumentError.new "Given object is not in the RefreshStack" unless @stack.include? obj
      return if obj == @stack.first
      ind = @stack.index obj
      (@stack[ind], @stack[ind - 1]) = @stack[(ind - 1)..ind]
    end

    def move_to_top obj
      # Assuming obj is found in @stack, makes obj the last item in @stack.

      raise CUIArgumentError.new "Given object is not in the RefreshStack" unless @stack.include? obj
      return if obj == @stack.last
      @stack.push (@stack.delete obj)
    end

    def move_to_bottom obj
      # Assuming obj is found in @stack, makes obj the first item in @stack.

      raise CUIArgumentError.new "Given object is not in the RefreshStack" unless @stack.include? obj
      return if obj == @stack.first
      @stack.unshift (@stack.delete obj)
    end

    def clear
      @stack = []
    end

    def noutrefresh
      @cui.event self, RefreshEvent
      if STDSCR
        STDSCR.clear
        STDSCR.noutrefresh
      end
      @stack.each do |obj|
        obj.noutrefresh if obj.respond_to? :noutrefresh
      end
    end
  end

  class DebugEvent < Event
    attr_reader :msg
    def initialize arg = {}
      super
      @msg = arg[:msg] if arg.key? :msg
    end
  end

  class CPEvent < Event
    # Base class for all color pair events.
  end

  class CPNewEvent < Event
    # If a color pair is created, this event gets sent.
  end

  class CPChangeEvent < CPEvent
    # If a color pair is changed, this event gets sent.

    attr_reader :fg_change, :bg_change

    def initialize arg = {}
      super
      [:fg_change, :bg_change].each do |attr|
        self.instance_variable_set "@#{attr_to_s}", (arg.key? attr)? arg[attr] : false
      end
    end
  end

  class CP < Object
    attr_reader :cp, :fg, :bg
    
    @@cpcount = 1

    def initialize arg = {}
      super
      @cp = @@cpcount
      @fg = (arg.key? :fg)? arg[:fg] : Curses::COLOR_WHITE
      @bg = (arg.key? :bg)? arg[:bg] : Curses::COLOR_BLACK
      Curses.init_pair @cp, @fg, @bg
      @@cpcount += 1
      @cui.event self, CPNewEvent
    end

    def fg= fg
      if fg != @fg
        @fg = fg
        Curses.init_pair @cp, @fg, @bg
        @cui.event self, CPChangeEvent, :fg_change => true
      end
    end

    def bg= bg
      if bg != @bg
        @bg = bg
        Curses.init_pair @cp, @fg, @bg
        @cui.event self, CPChangeEvent, :bg_change => true
      end
    end

    def to_i
      return @cp
    end

    def to_cp
      return Curses::color_pair @cp
    end
  end

  class DisplayableObjectEvent < Event
    # Parent class for all events involving DisplayableObjects.
  end

  class DisplayableObjectChangeEvent < DisplayableObjectEvent
    # If a DisplayableObject's position or size changes, one of these gets
    # pushed onto the event queue.

    attr_reader :resize, :move

    def initialize arg = {}
      [:resize, :move].each do |attr|
        self.instance_variable_set "@#{attr.to_s}", (arg.key? attr)? arg[attr] : false
      end
      super
    end
  end

  class DisplayableObject < Object
    # Displayable objects are graphically displayable; they have dimensions and
    # a position on the screen.

    attr_reader :width, :height, :x, :y, :focusable

    def initialize arg = {}
      super
      [:width, :height, :x, :y].each do |attr|
        next unless arg.key? attr
        self.instance_variable_set "@#{attr.to_s}", arg[attr]
      end
      @x ||= 0
      @y ||= 0
      @width ||= 1
      @height ||= 1
    end

    def resize height, width
      # Does work that a lot of child objects will need done -- sets the
      # object's dimensions.

      @height = height
      @width = width
      @cui.event self, DisplayableObjectChangeEvent, :resize => true
    end

    def height= height
      # Sets the object's height, returning true if it changed and false if not.

      return self.resize height, @width
    end

    def width= width
      # Likewise with width.

      return self.resize @height, width
    end

    def move y, x
      # Similar to resize, this sets the object's position.

      @y = y
      @x = x
      @cui.event self, DisplayableObjectChangeEvent, :move => true
    end

    def y= y
      return self.move y, @x
    end

    def x= x
      return self.move @y, x
    end

    def abs_within? y, x
      # Returns true if the absolute screen coordinates given lie within the
      # object, and false if not.

      # First determine the absolute boundaries of this object. If it's a
      # ContainerObject, it will respond to abs_x and abs_y.
      if self.respond_to? :abs_x
        x0 = self.abs_x
      else
        x0 = @x
      end
      if self.respond_to? :abs_y
        y0 = self.abs_y
      else
        y0 = @y
      end
      x1 = x0 + @width - 1
      y1 = y0 + @height - 1
      return true if x >= x0 and x <= x1 and y >= y0 and y <= y1
      return false
    end

    def mouse_within? m
      # Given a Curses::MouseEvent, uses abs_within? to determine whether the
      # mouse event took place within the object.

      return abs_within? m.y, m.x
    end
  end

  class ContainerObject < DisplayableObject
  end

  class Window < ContainerObject
  end

  class RootWindow < Window
    # Class that exists only to define RootWindow for STDSCR.
    def initialize arg = {}
      # Note that this does NOT call 'super'.
      @is_root = true
      @curses_window = Curses.stdscr
      @focusable = false
    end

    def resize height, width
      return false
    end

    def width
      return Curses.cols
    end

    def width= width
      return false
    end

    def height
      return Curses.lines
    end

    def height= height
      return false
    end

    def x
      return 0
    end

    def x= x
      return false
    end

    def y
      return 0
    end

    def y= y
      return false
    end

    def container
      return self
    end

    def root?
      return true
    end
  end

  STDSCR = RootWindow.new {}

  class ContainerObject < DisplayableObject
    # This class is for graphical objects that can contain or be contained by
    # other objects, as opposed to graphical objects that don't participate in
    # this containment structure.

    include Container

    extend Forwardable

    def_delegators :@keyobj, :getch, :getstr, :keypad, :nodelay, :nodelay=

    attr_reader :container, :contents, :keyobj

    def initialize arg = {}
      super
      [:container, :contents, :focusable].each do |attr|
        next unless arg.key? attr
        self.instance_variable_set "@#{attr.to_s}", arg[attr]
      end
      @container ||= STDSCR
      @width = @container.width if @width == 0
      @height = @container.height if @height == 0
      @contents ||= []
      @contents.each do |obj|
        obj.container = self if obj and obj.respond_to? :container=
      end
    end

    def container= cont
      raise CUIContainmentError.new "Trying to put a ContainerObject into something not a ContainerObject (#{cont.class})" unless cont.kind_of? ContainerObject
      @container = cont
    end

    def push obj
      raise CUIContainmentError.new "Trying to contain a non-ContainerObject (#{obj.class})" unless obj.kind_of? ContainerObject
      obj.container = self
      @contents.push obj
    end

    def contents= contents
      @contents.each { |c| c.close if c.respond_to? :close }
      contents.each do |obj|
        obj.container = self
      end
      @contents = contents
    end

    def noutrefresh_contents
      # If there are any @contents, refresh each one in turn.
      @contents.each do |obj|
        if obj.respond_to? :noutrefresh
          obj.noutrefresh
        end
      end
    end

    def noutrefresh
      # This will typically only be called as "super" from a subclass.
      if self.kind_of? ScrollBar and self.container.nil?
        raise RuntimeError.new "Nil container! #{self.class} '#{self.name}'"
      end
      @cui.event self, RefreshEvent if @cui.respond_to? :event
      self.noutrefresh_contents if @contents and @contents.respond_to? :each
    end

    def focusable= boolean
      # Sets the @focusable flag.

      raise CUIArgumentError.new "Attempted to set focusable flag to a non-Boolean value (#{boolean.class}, #{boolean})" if boolean != true and boolean != false
      @focusable = boolean
    end

    def focusable?
      # Returns the @focusable flag.
      return @focusable
    end

    def blocking?
      return nil unless @keyobj
      return !@keyobj.nodelay
    end

    def blocking= boolean
      return nil unless @keyobj
      @keyobj.nodelay = !boolean
    end

    def close
      # Goes through any @contents and closes everything.
      @contents.each do |obj|
        obj.close if obj.respond_to? :close
      end
    end
  end

  class ContainerFrameObject < ContainerObject
    # This is a class for objects such as BorderedWindow and ScrollWindow that
    # may contain either zero or one other object, which must exist in a fixed
    # position within that object.

    def initialize arg = {}
      super
      # Never more than 1 object in @contents.
      @contents = [@contents[0]] if @contents.size > 1
    end
  end

  class WindowEvent < Event
    # This is a base class for events sent by Window objects, so a listener
    # could ask to be notified if any such event occurred.
  end

  class WindowOpenEvent < WindowEvent
    # This is send when a new Window is created.
  end

  class WindowCloseEvent < WindowEvent
    # This is sent by Window#close.
  end

  class Window < ContainerObject
    # Makes a window. This is really just a wrapper around Curses::Window. The
    # difference is that it can contain and be contained by other Curses::Ui
    # objects, and it is linked into the Curses::Ui event system. Note that the
    # :x and :y placement coordinates are relative to its :container. Note also
    # that if no :container is given, the default container is
    # Curses::Ui::STDSCR, which is just the Curses::Ui wrapper around
    # Curses::stdscr.

    extend Forwardable

    def_delegators :@curses_window, :<<, :addch, :addstr, :attroff, :attron,
                   :attrset, :bkgd, :bkgdset, :box, :border, :clear, :clrtoeol,
                   :colorset, :curx, :cury, :delch, :deleteln, :getbkgd,
                   :getch, :getstr, :idlok, :inch, :insch, :insertln, :keypad,
                   :nodelay, :nodelay=, :scrl, :scroll, :scrollok, :setpos,
                   :setscrreg, :standend, :standout, :timeout=, :nil?

    attr_reader :curses_window

    def initialize arg = {}
      super
      [:curses_window].each do |attr|
        next unless arg.key? attr
        self.instance_variable_set "@#{attr.to_s}", arg[attr]
      end
      @container ||= STDSCR
      @curses_window ||= Curses::Window.new(@height, @width,
                                            @container.abs_y + @y,
                                            @container.abs_x + @x)
      @keyobj = @curses_window
      @cui.event self, WindowOpenEvent
    end

    def noutrefresh
      # If a Window has any @contents, the content in @curses_window will serve
      # as the background for that in @contents. If there are no @contents, it
      # doesn't matter which we call first. But the fact is that using 'super'
      # will call ContainerObject#noutrefresh and refresh the @contents, if
      # any. So call 'super' after refreshing @curses_window.

      @curses_window.noutrefresh
      super
    end

    def move y, x
      super
      @curses_window.move(@container.abs_y + @y,
                          @container.abs_x + @x)
    end

    def resize height, width
      super
      @curses_window.resize(@height, @width)
    end

    def close
      @curses_window.close
      @curses_window = nil
      @container = nil
      @cui.event self, WindowCloseEvent
    end

    def subwin height, width, y, x
      sub = @curses_window.subwin height, width, y, x
      return Curses::Ui::Window.new :container => self,
                                    :height => height,
                                    :width => width,
                                    :y => x,
                                    :x => y,
                                    :curses_window => sub
    end
  end

  class BorderedWindowEvent < Event
  end

  class BorderedWindowChangeEvent < Event
  end

  class BorderedWindowBorderChangeEvent < Event
  end

  class BorderedWindow < ContainerFrameObject
    # Makes a window with a border. Really this is just a window inside
    # another, offset by one row and one column and two characters smaller in
    # each dimension. The outer window contains the border, while the inner
    # window, smaller but displayed on top, contains whatever the window
    # contains. This class can be used as part of other classes -- anything
    # that needs a border.

    # For those unaware of why this is needed, remember that the normal curses
    # border function doesn't actually maintain that border; it just draws
    # characters inside the edges of the window. They can be overwritten like
    # any other characters in the window. With this class, code can write to
    # the inner window, and curses itself will prevent it from overwriting the
    # border, which is in a separate window.

    # BorderedWindows always have borders; the content window will always be
    # inset by 1 character in both vertical and horizontal dimensions all the
    # way around from the BorderedWindow's dimension. If you want a window
    # without borders, just use a Window.

    # This also serves as a simple example/test of constructing a complex
    # ContainerObject (complex, but not TOO complex), as it has a "slot" into
    # which one could insert an existing ContainerObject, namely the window
    # around which the border goes. This is done by setting the :contained
    # argument at creation, or changing it by assigning to the
    # BorderedWindow#contained= attribute. If no :contained object is specified
    # at creation, a new Curses::Ui::Window of the appropriate size will be
    # created. If the :surround flag is specified at creation, the frame will
    # be constructed around the existing object, but otherwise, any :contained
    # object will be resized to fit the given :width and :height and moved
    # within the frame.

    extend Forwardable

    def_delegators :@main_window, :<<, :addch, :addstr, :attroff, :attron,
                   :attrset, :bkgd, :bkgdset, :box, :border, :clear, :clrtoeol,
                   :colorset, :curx, :cury, :delch, :deleteln, :getbkgd,
                   :idlok, :inch, :insch, :insertln, :scrl, :scroll, :scrollok,
                   :setpos, :setscrreg, :standend, :standout, :timeout=

    attr_reader :focus_border, :unfocus_border, :border_fgcol, :border_bgcol,
                :border_window, :title, :title_fgcol, :title_bgcol

    attr_accessor :focused

    def initialize arg = {}
      super
      [:focus_border, :unfocus_border, :border_fgcol, :border_bgcol, :title,
       :title_fgcol, :title_bgcol].each do |attr|
        next unless arg.key? attr
        self.instance_variable_set "@#{attr.to_s}", arg[attr]
      end
      @focus_border ||= :single
      @unfocus_border ||= :dotted
      @border_fgcol ||= Curses::COLOR_WHITE
      @border_bgcol ||= Curses::COLOR_BLACK
      @border_window = @cui.new_window :name => "#{@name}/bwin",
                                       :container => self,
                                       :height => @height,
                                       :width => @width,
                                       :x => 0,
                                       :y => 0
      @bcp = @cui.new_cp :fg => @border_fgcol,
                         :bg => @border_bgcol
      @title_fgcol ||= Curses::COLOR_WHITE
      @title_bgcol ||= Curses::COLOR_BLACK
      @tcp = @cui.new_cp :fg => @title_fgcol,
                         :bg => @title_bgcol

      @main_window = nil
      @keyobj = nil
      # Because of the initializers of ContainerObject and
      # ContainerFrameObject, @contents is guaranteed to be an Array that
      # contains no more than 1 item, though it may be empty.
      if @contents.size == 1
        @main_window = contents[0]
        @keyobj = @main_window
        # ContainerObject's initializer already does this:
#        @contents[0].container = self
        # This is subclass specific:
        @contents[0].resize @height - 2, @width - 2
        @contents[0].move 1, 1
      end
    end

    def noutrefresh_border_window
      @border_window.attrset (@bcp.to_cp | Curses::A_BOLD)
      if @focused
        @border_window.border :preset => @focus_border
      else
        @border_window.border :preset => @unfocus_border
      end
      unless @title.nil? or @title.empty?
        tstr = " #{@title} "
        @border_window.attrset (@tcp.to_cp) | Curses::A_BOLD
        @border_window.setpos 0, (@width - tstr.size)/2
        @border_window.addstr tstr
      end
      @border_window.noutrefresh
    end

    def noutrefresh
      # We definitely want to call 'super' (going up to
      # ContainerObject#noutrefresh) to refresh the @contents after refreshing
      # @border_window, or the blank interior of @border_window will overwrite
      # anything put there by the @contents.

      noutrefresh_border_window
      super
    end

    def contents= obj
      # Changing which object is contained within the border. This will attempt
      # to resize the contained object to fit within the border; it will not
      # resize the border to fit around the object.

      super [obj]
      obj.resize @height - 2, @width - 2
      obj.move 1, 1
      @main_window = obj
    end

    def resize height, width
      super
      self.border_window.resize height, width
      self.contents[0].resize height - 2, width - 2
    end

    def focus_border= border
      # Deal with changing the focus border.
      return if border == @focus_border
      @focus_border = border
      self.noutrefresh
      @cui.event self, BorderedWindowBorderChangeEvent
    end

    def unfocus_border= border
      # Deal with changing the unfocus border.
      return if border == @unfocus_border
      @unfocus_border = border
      self.noutrefresh
      @cui.event self, BorderedWindowBorderChangeEvent
    end

    def border_fgcolor= col
      return if col == @border_fgcolor
      @bcp.fg = col
      self.noutrefresh
      @cui.event self, BorderedWindowBorderChangeEvent
    end

    def border_bgcolor= col
      return if col == @border_bgcolor
      @bcp.bg = col
      self.noutrefresh
      @cui.event self, BorderedWindowBorderChangeEvent
    end
  end

  class ScrollBarEvent < Event
  end

  class ScrollBar < Window
    # Base class for VerticalScrollBar and HorizontalScrollBar

    DEFAULT_BAR_CHAR = "\u2591"
    DEFAULT_BOX_CHAR = "\u2588"

    attr_reader :fraction, :bar_char, :bar_fgcol, :bar_bgcol, :box_char,
                :box_fgcol, :box_bgcol

    def initialize arg = {}
      super
      [:fraction, :bar_char, :bar_fgcol, :bar_bgcol, :box_char, :box_fgcol,
       :box_bgcol].each do |attr|
        next unless arg.key? attr
        self.instance_variable_set "@#{attr.to_s}", arg[attr]
      end
      @fraction ||= 0.0
      @bar_char ||= DEFAULT_BAR_CHAR
      @bar_char = @bar_char[0] if @bar_char.size > 1
      @bar_fgcol ||= Curses::COLOR_WHITE
      @bar_bgcol ||= Curses::COLOR_BLACK
      @box_char ||= DEFAULT_BOX_CHAR
      @box_char = @box_char[0] if @box_char.size > 1
      @box_fgcol ||= Curses::COLOR_WHITE
      @box_bgcol ||= Curses::COLOR_BLACK
    end

    def fraction= fraction
      return if fraction == @fraction
      @fraction = fraction
    end
  end

  class VerticalScrollBar < ScrollBar

    def initialize arg = {}
      arg[:width] = 1
      super
    end

    def noutrefresh
      @bar_cp ||= @cui.new_cp :fg => @bar_fgcol,
                              :bg => @bar_bgcol
      self.attrset @bar_cp.to_cp
      (0...self.height).each do |row|
        self.setpos row, 0
        self.addstr @bar_char
      end
      self.setpos (@fraction * self.height.to_f).to_i, 0
      self.addstr @box_char
      super
    end
  end

  class HorizontalScrollBar < ScrollBar

    def initialize arg = {}
      arg[:height] = 1
      super
    end

    def noutrefresh
      @bar_cp ||= @cui.new_cp :fg => @bar_fgcol,
                              :bg => @bar_bgcol
      self.attrset @bar_cp.to_cp
      self.setpos 0, 0
      self.addstr @bar_char*self.width
      self.setpos 0, (@fraction * self.width.to_f).to_i
      self.addstr @box_char
      super
    end
  end

  class ScrollWindowEvent < Event
  end

  class ScrollWindowChangeEvent < Event
  end

  class ScrollWindowBorderChangeEvent < Event
  end

  class ScrollWindow < ContainerFrameObject
    # Makes a window with scroll bars. Really this is just a set of three
    # windows, a main text window and vertical and horizontal scroll bars. The
    # width and height of the ScrollWindow is the width and height of the whole
    # assembly; i.e. the main window is one smaller than this in width and
    # height.

    extend Forwardable

    def_delegators :@main_window, :<<, :addch, :addstr, :attroff, :attron,
                   :attrset, :bkgd, :bkgdset, :box, :border, :clear, :clrtoeol,
                   :colorset, :curx, :cury, :delch, :deleteln, :getbkgd,
                   :getch, :getstr, :idlok, :inch, :insch, :insertln, :keypad,
                   :nodelay, :nodelay=, :scrl, :scroll, :scrollok, :setpos,
                   :setscrreg, :standend, :standout, :timeout=

    attr_reader :vbar, :hbar

    def initialize arg = {}
      super
      [:bar_char, :bar_fgcol, :bar_bgcol, :box_fgcol, :box_bgcol,
       :box_char].each do
        |attr|
        next unless arg.key? attr
        self.instance_variable_set "@#{attr.to_s}", arg[attr]
      end

      # Make the scroll bars.
      @vbar = @cui.new_vertical_scroll_bar :name => "#{@name}/vbar",
                                           :container => self,
                                           :height => @height - 1,
                                           :x => @width - 1,
                                           :y => 0,
                                           :bar_char => @bar_char || nil,
                                           :bar_fgcol => @bar_fgcol || nil,
                                           :bar_bgcol => @bar_bgcol || nil,
                                           :box_char => @box_char || nil,
                                           :box_fgcol => @box_fgcol || nil,
                                           :box_bgcol => @box_bgcol || nil
      @hbar = @cui.new_horizontal_scroll_bar :name => "#{@name}/hbar",
                                             :container => self,
                                             :width => @width - 1,
                                             :x => 0,
                                             :y => @height - 1,
                                             :bar_char => @bar_char || nil,
                                             :bar_fgcol => @bar_fgcol || nil,
                                             :bar_bgcol => @bar_bgcol || nil,
                                             :box_char => @box_char || nil,
                                             :box_fgcol => @box_fgcol || nil,
                                             :box_bgcol => @box_bgcol || nil

      @main_window = nil
      @keyobj = nil
      if @contents.size == 1
        @main_window = @contents[0]
        @keyobj = @main_window
        @contents[0].resize @height - 1, @width - 1
        @contents[0].move 0, 0
      end
    end

    def noutrefresh_scroll_bars
      @vbar.noutrefresh
      @hbar.noutrefresh
    end

    def noutrefresh
      noutrefresh_scroll_bars
      super
    end

    def contents= obj
      # Changing which object is contained within self. This will attempt to
      # resize the contained object to fit within self; it will not resize self
      # to fit around the object.

      super [obj]
      obj.resize @height - 1, @width - 1
      obj.move 0, 0
      @main_window = obj
    end

    def move y, x
      super
      self.vbar.move y, self.width - 1
      self.hbar.move self.height - 1, 0
      self.contents[0].move y, x
    end

    def resize height, width
      super
      self.vbar.resize height - 1, 1
      self.hbar.resize 1, width - 1
      self.contents[0].resize height - 1, width - 1
    end
  end

  class PadEvent < Event
  end

  class PadCreateEvent < PadEvent
  end

  class Pad < ContainerObject
    # This is similar to a Curses::Pad object but has more screen presence. The
    # :width, :height, :x, and :y parameters define where on the screen the
    # item should appear. The :pad_width and :pad_height parameters refer to
    # the dimensions of the actual pad object, a rectangular buffer whose
    # characters need not all be visible. The :pad_x and :pad_y parameters are
    # the coordinates within the buffer of the upper left-hand corner of the
    # box visible on screen. This allows you to print data to a buffer and
    # scroll it around.

    # Pads have both an actual size and a "viewport," a rectangle on the screen
    # that shows a portion of the data in the pad. The pad's regular width,
    # height, x, and y attributes define the size and screen position of the
    # viewport. The pad_width and pad_height attributes define the dimensions
    # of the actual data area where the content is stored. Then pad_x and pad_y
    # define the upper left corner within the data area of the portion of that
    # content that is visible in the screen viewport.

    # Think of a piece of paper with a rectangular hole cut in it, then think
    # of holding it up to a larger document and only seeing a portion of that
    # document at any one time. The document is pad_width by pad_height
    # characters in size. The rectangular hole is width * height characters in
    # size, located on your screen with its upper-left corner at row y, column
    # x. You can slide the document around beneath the hole to view different
    # portions of it (this is changing pad_x and pad_y).

    extend Forwardable

    def_delegators :@curses_pad, :<<, :addch, :attroff, :attron, :attrset,
                   :bkgd, :bkgdset, :box, :border, :clrtoeol, :colorset,
                   :delch, :deleteln, :getbkgd, :getch, :getstr, :idlok, :inch,
                   :insch, :insertln, :keypad, :nodelay, :nodelay=, :scrl,
                   :scroll, :scrollok, :setscrreg, :standend, :standout,
                   :timeout=, :nil?

    attr_reader :curses_pad, :pad_x, :pad_y, :pad_height, :pad_width, :text,
                :text_longest, :cur_y, :cur_x

    def initialize arg = {}
      super
      [:pad_width, :pad_height, :pad_x, :pad_y].each do |attr|
        next unless arg.key? attr
        self.instance_variable_set "@#{attr.to_s}", arg[attr]
      end
      @container ||= STDSCR
      raise CUIArgumentError.new "Pad has nil x" if @x.nil?
      raise CUIArgumentError.new "Pad has nil y" if @y.nil?
      # Curses does not accept pads with either dimension less than 1; it
      # considers them nil.
      @pad_width ||= 1
      @pad_width = 1 unless @pad_width >= 1
      @pad_height ||= 1
      @pad_height = 1 unless @pad_height >= 1
      @curses_pad = Curses::Pad.new @pad_height, @pad_width
      @pad_x ||= 0
      @pad_y ||= 0
      @text = [' ']
      @text_longest = 1
      @curses_pad.clear
      @curses_pad.setpos 0, 0
      @cur_x = 0
      @cur_y = 0
      @cui.event self, PadCreateEvent
      @keyobj = @curses_pad
    end

    def noutrefresh_pad
      absy = self.abs_y
      absx = self.abs_x
      @curses_pad.noutrefresh(@pad_y, @pad_x,
                              absy, absx,
                              absy + @height - 1,
                              absx + @width - 1)
    end

    def noutrefresh
      self.noutrefresh_pad
    end

    def pad_x= x
      return self.move_pad @pad_y, x
    end

    def pad_y= y
      return self.move_pad y, @pad_x
    end

    def move_pad y, x
      # Moves the pad viewport coordinates.

      # If there isn't even an attempt to change the coordinates, leave.
      x_changed = (x != @pad_x)
      y_changed = (y != @pad_y)
#      return false unless x_changed or y_changed

      # Make sure we won't be displaying anything outside the pad.
      x = 0 if x < 0
      maxx = [@text_longest - @width, 0].max
      x = maxx if x > maxx
      y = 0 if y < 0
      maxy = [@text.size - @height, 0].max
      y = maxy if y > maxy

      # If this means there are no changes, leave.
      x_changed = (x != @pad_x)
      y_changed = (y != @pad_y)
#      return unless x_changed or y_changed

      # Set the coordinates. Calling Pad#noutrefresh will put them into effect.
      @pad_x = x
      @pad_y = y
      return true
    end

    def pad_height= height
      return self.resize_pad height, @pad_width
    end

    def pad_width= width
      return self.resize_pad @pad_height, width
    end

    def resize_pad height, width
      height_changed = (height != @pad_height)
      width_changed = (width != @pad_width)
#      return false unless height_changed or width_changed
      @pad_height = height
      @pad_width = width
      @curses_pad.resize @pad_height, @pad_width
      return true
    end

    def cur_y= y
      return self.setpos y, @x
    end

    def cur_x= x
      return self.setpos @y, x
    end

    def clear
      @text = [' ']
      @cur_y = 0
      @cur_x = 0
      @curses_pad.clear
      self.resize_pad 1, 1
      @curses_pad.setpos 0, 0
    end

    def erase
      @text = [' ']
      @cur_y = 0
      @cur_x = 0
      @curses_pad.erase
      self.resize_pad 1, 1
      @curses_pad.setpos 0, 0
    end

    def setpos y, x
      # Set the pad cursor to position (y, x). Does not allow coordinates to be
      # negative. Does allow them to be greater than the current number of
      # rows/columns in the pad -- resizes the pad to accommodate.
      return false unless y != @cur_y or x != $cur_x
      y = 0 if y < 0
      x = 0 if x < 0
      if y >= @pad_height or x >= @pad_width
        self.resize_pad [y + 1, @pad_height].max, [x + 1, @pad_width].max
      end
      @cur_y = y
      @cur_x = x
      @curses_pad.setpos y, x
      return true
    end

    def text_set_longest
      longest = @text.max_by { |s| s.size }
      @text_longest = longest.size
      return @text_longest
    end

    def puts str = ''
      # Calls addstr but puts a newline at the end.
      return self.addstr "#{str}\n"
    end

    def addstr str = ''
      # Updates the @text array and calls @curses_pad.addstr with the same
      # text, starting at (@cur_y, @cur_x). If @text isn't large enough,
      # enlarges it. If the @curses_pad isn't large enough, enlarges it as
      # well. Unfortunately there's no quick way to get data back out of a
      # Curses::Pad (one character at a time only), hence the need to keep a
      # separate @text. Curses allows you to print data to pads and windows
      # using attributes, so you can use colors, bold, inverse, etc., but that
      # doesn't get saved to @text.

      # We will return the return value of the last addstr call that
      # occurs. Define a variable to hold it.
      retval = nil

      # Might be various control characters in the text, some of which we might
      # want to pay attention to (right now I'm thinking newlines). For speed
      # I'd like runs of straightforward text to not be dealt with one
      # character at a time. But I'd like to preserve the control
      # characters. So we have some regular expressions here: the characters we
      # filter out and the characters we split on.
      filterout = /[\x01-\x09\x0b-\x1f]+/

      # Get the position we think we should be at in the pad.
      y = @cur_y
      x = @cur_x

      # Keep track of text we've handled and text we haven't.
      unhandled = str.sub(filterout, '')
      handled = ''

      # And loop.
      loop do
        # If there is no unhandled text, jump out of the loop.
        break if unhandled.empty?

        # Take characters from unhandled until we hit a control character.
        md = unhandled.match(/\A([^\n]*)([\n])(.*)\Z/m)

        # Decide what control character to deal with after printing 'handling'
        # (if any).
        # Results for: md = foo.match(/\A([^\n]*)([\n])(.*)\Z/m)
        # foo = "": md = nil
        # foo = "\na": md.captures = [ "", "\n", "a" ]
        # foo = "\n": md.capures = [ "", "\n", "" ]
        # foo = "a": md = nil
        # foo = "a\n": md.captures = [ "a", "\n", "" ]
        # foo = "a\nb": md.captures = [ "a", "\n", "b" ]
        if md.nil?
          # Since we have already exited the loop if 'unhandled' is empty, this
          # means that whatever's in 'unhandled', it isn't an MCC.
          handling = unhandled
          control = nil
          unhandled = ''
        else
          (handling, control, unhandled) = md.captures
        end

        # Add a line to @text if necessary.
        if y >= @text.size
          (@text.size..y).each do |count|
            @text.push ' '
          end
        end
        # Likewise, make sure the pad has enough rows.
        self.pad_height = y + 1 if @pad_height <= y
        # Find the current row in @text and enlarge it if necessary.
        cursize = @text[y].size
        if x > cursize
          @text[y] += ' '*(x - cursize)
        end
        # Likewise, make sure the pad is wide enough.
        self.pad_width = x + handling.size + 1 if @pad_width <= x + handling.size
        # Insert 'handling'.
        @text[y].insert x, handling
        @curses_pad.setpos y, x
        retval = @curses_pad.addstr handling
        x += handling.size
        # Now deal with the control character, if any.
        unless control.nil?
          if control == "\n"
            y += 1
            x = 0
          end
        end
        handled += handling
        handled += control unless control.nil?
      end
      # Remember the position.
      @cur_y = y
      @cur_x = x
      self.text_set_longest
      return retval
    end
  end

  class TextViewer < ContainerObject
    # This is just like a BorderWindow that contains a ScrollWindow that
    # contains a Pad. And the Pad's position is hooked to the ScrollWindow's
    # scrollbars.

    extend Forwardable

    def_delegators :@pad, :attrset, :addstr, :setpos, :clear, :erase,
                   :pad_height, :pad_width, :pad_x, :pad_x=, :pad_y, :pad_y=,
                   :puts, :text

    def_delegators :@bwin, :focus_border, :focus_border=, :unfocus_border,
                   :unfocus_border=, :border_bgcol, :border_bgcol=,
                   :border_fgcol, :border_fgcol=, :focused, :focused=

    attr_reader :pad, :bwin, :swin

    def initialize arg = {}
      super
      [:focus_border, :unfocus_border, :border_bgcol, :border_fgcol, :title,
       :title_bgcol, :title_fgcol, :bar_char, :bar_fgcol, :bar_bgcol,
       :box_char, :box_fgcol, :box_bgcol, :pad_width, :pad_height, :pad_x,
       :pad_y].each do
       |attr|
        next unless arg.key? attr
        self.instance_variable_set "@#{attr.to_s}", arg[attr]
      end

      newargs = {:name => "#{@name}/bwin"}
      [:width, :height, :x, :y, :focus_border, :unfocus_border, :border_bgcol,
       :border_fgcol, :title, :title_bgcol, :title_fgcol].each do |attr|
        next unless arg.key? attr
        newargs[attr] = arg[attr]
      end
      @bwin = @cui.new_bordered_window newargs

      newargs = {:name => "#{@name}/swin",
                 :width => @width - 2,
                 :height => @height - 2,
                 :x => @x + 1,
                 :y => @y + 1}
      [:bar_char, :bar_fgcol, :bar_bgcol, :box_char, :box_fgcol,
       :box_bgcol].each do |attr|
        next unless arg.key? attr
        newargs[attr] = arg[attr]
      end
      @swin = @cui.new_scroll_window newargs

      newargs = {:name => "#{@name}/pad",
                 :width => @width - 3,
                 :height => @height - 3,
                 :x => @x + 1,
                 :y => @y + 1}
      [:pad_width, :pad_height, :pad_x, :pad_y].each do |attr|
        next unless arg.key? attr
        newargs[attr] = arg[attr]
      end
      @pad = @cui.new_pad newargs
      @keyobj = @pad
    end

    def noutrefresh_border
      @bwin.noutrefresh
    end

    def noutrefresh_scroll
      if @pad.text_longest > @width
        @swin.hbar.fraction = @pad.pad_x.to_f/(@pad.text_longest.to_f - @width.to_f)
      end
      if @pad.text.size > @height
        @swin.vbar.fraction = @pad.pad_y.to_f/(@pad.text.size.to_f - @height.to_f)
      end
      @swin.noutrefresh
    end

    def noutrefresh_pad
      @pad.noutrefresh
    end

    def noutrefresh
      self.noutrefresh_border
      self.noutrefresh_scroll
      self.noutrefresh_pad
      super
    end

    def handle_mouse m
      # We've gotten a Curses::MouseEvent. Where is it? We're only concerned if
      # it's within one of the scroll bars.

      scrollbar_clicked = false

      # First check the horizontal one.
      if @swin.hbar.mouse_within? m
        scrollbar_clicked = true
        if @pad.text_longest > @width
          @swin.hbar.fraction = (m.x.to_f - @swin.hbar.abs_x.to_f)/(@swin.hbar.width.to_f)
          @pad.pad_x = (@swin.hbar.fraction*(@pad.text_longest.to_f - @pad.width.to_f)).round.to_i
          self.noutrefresh
          @cui.refresh
        end

        # Now check the vertical one.
      elsif @swin.vbar.mouse_within? m
        scrollbar_clicked = true
        if @pad.text.size > @height
          @swin.vbar.fraction = (m.y.to_f - @swin.vbar.abs_y.to_f)/(@swin.vbar.height.to_f)
          @pad.pad_y = (@swin.vbar.fraction*(@pad.text.size.to_f - @pad.height.to_f)).round.to_i
          self.noutrefresh
          @cui.refresh
        end
      end
      return scrollbar_clicked
    end
  end

  class Box < ContainerObject
    # A container object that automatically arranges the things it contains
    # (i.e. setting their x and y attributes automatically).

    def noutrefresh
      self.justify
      super
    end
  end

  class HBox < Box
    # A container object with a list of other objects displayed horizontally.

    attr_reader :vjust

    def initialize arg = {}
      super
      # :top, :center, and :bottom are valid values for :vjust.
      if arg.key? :vjust
        self.vjust = arg[:vjust]
      else
        @vjust = :center
      end
    end

    def justify
      # Rearrange the positions of the objects to fit them all in. We hope.
      width_sum = @contents.reduce(0) { |sum, obj| sum + obj.width }
      if width_sum > @width
        # The bad outcome: the total is too big. For now keep their proportions
        # relative to each other and make them just fit.
        shrink_factor = @width.to_f/width_sum.to_f
        @contents.each do |obj|
          obj.width = (obj.width.to_f*shrink_factor).round.to_i
        end
        width_sum = @width
      end
      # Now we know that everything will fit.
      spacing = (@width.to_f - width_sum.to_f)/(@contents.size.to_f + 1.0)
      x = spacing
      @contents.each do |obj|
        # As for the height, center it and make sure it doesn't exceed @height.
        obj.y = [ (@height - obj.height)/2, 0 ].max
        obj.height = [ obj.height, @height ].min
        obj.x = x.round.to_i
        x += obj.width
        x += spacing
      end
    end

    def vjust= just
      unless [:top, :center, :bottom].include? just
        raise CUIArgumentError.new "Only :top, :center, :bottom are allowed"
      end
      @vjust = just
    end
  end

  class VBox < Box
    # A container object with a list of other objects displayed vertically.

    attr_reader :hjust

    def initialize arg = {}
      super
      # :left, :center, and :right are valid values for :hjust.
      if arg.key? :hjust
        self.hjust = arg[:hjust]
      else
        @hjust = :center
      end
    end

    def justify
      # Rearrange the positions of the objects to fit them all in. We hope.
      height_sum = @contents.reduce(0) { |sum, obj| sum + obj.height }
      if height_sum > @height
        # The bad outcome: the total is too big. For now keep their proportions
        # relative to each other and make them just fit.
        shrink_factor = @height.to_f/height_sum.to_f
        @contents.each do |obj|
          obj.height = (obj.height.to_f*shrink_factor).round.to_i
        end
        height_sum = @height
      end
      # Now we know that everything will fit.
      spacing = (@height.to_f - height_sum.to_f)/(@contents.size.to_f + 1.0)
      y = spacing
      @contents.each do |obj|
        # As for the width, center it and make sure it doesn't exceed @width.
        if @hjust == :center
          obj.x = [ (@width - obj.width)/2, 0 ].max
        elsif @hjust == :right
          obj.x = [ @width - obj.width, 0 ].max
        else
          obj.x = 0
        end
        obj.width = [ obj.width, @width ].min
        obj.y = y.round.to_i
        y += obj.height.to_f
        y += spacing
      end
    end

    def hjust= just
      unless [:left, :center, :right].include? just
        raise CUIArgumentError.new "Only :left, :center, :right are allowed"
      end
      @hjust = just
    end
  end

  class Dialog < ContainerObject
    # Similar to TextViewer, this is a BorderedWindow that contains a VBox that
    # contains three Windows.

    extend Forwardable

    def_delegators :@bwin, :focus_border, :focus_border=, :unfocus_border,
                   :unfocus_border=, :border_bgcol, :border_bgcol=,
                   :border_fgcol, :border_fgcol=, :focused, :focused=

    attr_reader :bwin, :vbox, :msgwin, :spcwin, :optwin

    def initialize arg = {}
      super
      [:focus_border, :unfocus_border, :border_bgcol, :border_fgcol, :title,
       :title_bgcol, :title_fgcol, :bar_char, :bar_fgcol, :bar_bgcol,
       :box_char, :box_fgcol, :box_bgcol, :cp, :msg, :options].each do
       |attr|
       next unless arg.key? attr
       self.instance_variable_set "@#{attr.to_s}", arg[attr]
      end

      msglines = @msg.split "\n"
      msglongest = msglines.max { |a, b| a.size <=> b.size }
      optlongest = @options.values.max { |a, b| a.size <=> b.size }

      # Make the Window for msg
      newargs = {:name => "#{@name}/msgwin",
                 :height => msglines.size,
                 :width => msglongest.size + 1}
      @msgwin = @cui.new_window newargs

      # Make the Window for spacing
      newargs = {:name => "#{@name}/spcwin",
                 :height => 1,
                 :width => 1}
      @spcwin = @cui.new_window newargs

      # Make the Window for options
      newargs = {:name => "#{@name}/optwin",
                 :height => @options.size,
                 :width => optlongest.size + 1}
      @optwin = @cui.new_window newargs

      # Make the VBox
      newargs = {:name => "#{@name}/vbox",
                 :y => @y + 1,
                 :x => @x + 1,
                 :height => @height - 2,
                 :width => @width - 2,
                 :contents => [@msgwin, @spcwin, @optwin]}
      @vbox = @cui.new_vbox newargs

      # Make the BorderedWindow
      newargs = {:name => "#{@name}/bwin"}
      [:width, :height, :x, :y, :focus_border, :unfocus_border, :border_bgcol,
       :border_fgcol, :title, :title_bgcol, :title_fgcol].each do |attr|
        next unless arg.key? attr
        newargs[attr] = arg[attr]
      end
      newargs[:contents] = [@vbox]
      @bwin = @cui.new_bordered_window newargs
      @bwin.noutrefresh

#      @cui.event self, DebugEvent, :msg => "#{__method__} (#{__FILE__}/#{__LINE__}): @msgwin.(y, x) = (#{@msgwin.y}, #{@msgwin.x})"

      @msgwin.attrset @cp.to_cp || Curses::A_BOLD
      @msgwin.setpos 0, 0
      @msgwin.addstr @msg

      @optwin.attrset @cp.to_cp || Curses::A_BOLD
      @optwin.setpos 0, 0
      @optwin.addstr (@options.values.sort.join "\n")

      @contents = [@bwin]

      @keyobj = @optwin
    end
  end

  class ButtonClickEvent < Event
  end

  class Button < Window
    # Implements a button -- just a BorderedWindow containing a Window centered
    # around some text that can receive mouse clicks and generate ButtonClickEvents.

    attr_reader :label

    def initialize arg = {}
      super
      [:label].each do |attr|
        next unless arg.key? attr
        self.instance_variable_set "@#{attr}", arg[attr]
      end

      # Buttons get their width from their contents. Text should be short and
      # one line only.
      @label = (@label.split "\n", 2).first
      @width = @label.size + 4
      @height = 3
    end
  end
end
