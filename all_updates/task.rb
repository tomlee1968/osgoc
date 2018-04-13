require 'set'
require 'time'
require 'tzinfo'

class Task

  attr_accessor :system, :type, :id, :cmd, :param, :cmdsudo, :timereq,
                :complete, :started, :failcount, :lastattempt, :lastfail,
                :timestamp, :skip, :manual, :tmux_window, :waitforothers,
                :circ_checked, :ask

  attr_reader :deps

  def initialize arg = {}
    # Copy values to instance variables.
    [:system, :type, :id, :cmd, :param, :cmdsudo, :timereq, :complete, :started,
     :failcount, :lastattempt, :lastfail, :timestamp, :skip, :manual,
     :tmux_window, :waitforothers, :deps, :ask].each do |attr|
      next unless arg.key? attr
      self.instance_variable_set "@#{attr}", arg[attr]
    end
    # Some attributes have default values.
    @complete = false unless arg.key? :complete
    @started = false unless arg.key? :started
    @failcount = 0 unless arg.key? :failcount
    @lastattempt = nil unless arg.key? :lastattempt
    @lastfail = nil unless arg.key? :lastfail
    @skip = false unless arg.key? :skip
    @manual = false unless arg.key? :manual
    @waitforothers = false unless arg.key? :waitforothers
    @deps = Set.new unless arg.key? :deps
    @deps = Set.new @deps unless @deps.kind_of? Set
    @ask = true unless arg.key? :ask
    @circ_checked = false

    @@status = "Task.new: Task object successfully defined."
    @@ok = true
  end

  def deps= deps
    # Sets @deps to the argument. Only accepts arrays and sets. Returns true on
    # success, nil on failure.

    if deps.kind_of? Array
      @deps = Set.new deps
    elsif deps.kind_of? Set
      @deps = deps
    else
      @@status = "#{__method__}: Argument not Set or convertible (#{deps.class})"
      @@ok = false
      return nil
    end
    @@status = "#{__method__}: @deps successfully set."
    @@ok = true
    return true
  end

  def alarm_complete?
    unless self.alarm?
      @@status = "#{__method__.to_s}: Task is not an alarm clock."
      @@ok = false
      return nil
    end
    unless self.param
      @@status = "#{__method__.to_s}: Task has no param value."
      @@ok = false
      return nil
    end
    @@status = "#{__method__.to_s}: Successfully examined task."
    @@ok = true
    # If the task is already marked complete, go no further.
    return true if self.complete?
    timewait_return = nil
    if @type == 'time'
      timewait_return = self.timewait_complete?
    elsif @type == 'dstime'
      timewait_return = self.dstimewait_complete?
    else
      # Shouldn't happen.
      @@status = "#{__method__.to_s}: Alarm neither time nor dstime"
      @@ok = false
      return nil
    end
    self.mark_complete if timewait_return
    return timewait_return
  end

  def delay_complete?
    unless self.delay?
      @@status = "#{__method__.to_s}: Task is not of type '*delay' ('#{@type}' instead)"
      @@ok = false
      return nil
    end
    unless self.param
      @@status = "#{__method__.to_s}: Delay task has no param value."
      @@ok = false
      return nil
    end
    # If the complete flag has been set, don't test any further. Make it look
    # as if the timer has been completed (and started, if necessary).
    if @complete
      @@status = "#{__method__.to_s}: Successfully tested delay timer."
      @@ok = true
      @timestamp = Time.new unless @timestamp and Time.new >= @timestamp
      return true
    end
    unless @timestamp
      @@status = "#{__method__.to_s}: Timer has not been started."
      @@ok = false
      return nil
    end
    @@status = "#{__method__.to_s}: Successfully tested delay timer."
    @@ok = true
    if Time.new >= @timestamp
      self.mark_complete
      return true
    else
      return false
    end
  end

  def delay_start
    unless @type and @type =~ /delay$/
      @@status = "#{__method__.to_s}: Task is not of type '*delay' ('#{@type}')"
      @@ok = false
      return nil
    end
    unless @param
      @@status = "#{__method__.to_s}: Delay task has no param value"
      @@ok = false
      return nil
    end
    @timestamp = Time.new + @param.to_i
    self.mark_started
    return true
  end

  def depends_on *args
    # Given an argument list of tasks, arrays of tasks, or sets of tasks,
    # returns the number of tasks in the arguments that this task depends on.

    unless @deps and @deps.kind_of? Set
      raise "#{__method__}: @deps is not a Set (is a #{@deps.class}; @id = '#{@id}')"
    end
    count = 0
    args.each do |item|
      if item.kind_of? Array or item.kind_of? Set
        item.each do |i|
          count += self.depends_on i
        end
      elsif item.kind_of? Task or item.kind_of? String
        @deps.add item
        count += 1
      else
        raise "#{__method__}: .depends_on was called with illegal object (#{item.class})"
      end
    end
    @@status = "#{__method__}: #{count} items successfully added to Task object's 'deps' set."
    @@ok = count > 0
    return count
  end

  def depends_on? t
    # Given a task, returns true if self depends on the given task and false if
    # not.

    return false unless t.kind_of? Task
    return @deps.include? t
  end

  def unmet_deps
    # Returns an array of this task's unmet dependencies.

    return @deps.to_a.select { |d| !d.complete? }
  end

  def dep_grep proc
    # Given a Proc, runs that Proc on the task's dependencies and returns an
    # array of the prerequisite tasks for which the Proc evaluated to true.

    unless proc.kind_of? Proc
      @@status = "#{__method__}: Argument is not a Proc (is '#{proc.class}')"
      @@ok = false
      return nil
    end
    matchers = @deps.to_a.select { |d| proc.call d }
    @@status = "#{__method__}: Dependency array searched."
    @@ok = true
    return matchers
  end

  def has_deps?
    # Returns true if the task has any dependencies and false if it doesn't.

    return @deps.size > 0
  end

  def deps_met?
    # Returns true if all the task's dependencies are met, or if it has no
    # dependencies. Returns false if there are any unmet dependencies. Returns
    # nil if there is a problem.

    # Return true if no dependencies.
    return true unless self.has_deps?
    @@status = "#{__method__.to_s}: Dependencies successfully tested."
    @@ok = true
    # If even one dependency is unmet, return false.
    @deps.each do |d|
      unless d.kind_of? Task
        @@status = "#{__method__.to_s}: #{@id} has a dependency that is not a Task"
        @@ok = false
        return nil
      end
      return false unless d.complete?
    end
    # If we're still here, all dependencies were met.
    return true
  end

  def alarm?
    # One type of 'timer' task, an 'alarm-clock' task is one whose type is
    # 'time' (or 'dstime', but that is archaic, as 'time' tasks now take DST
    # into account automatically assuming a correct timezone setting).
    unless @type
      @@status = "#{__method__.to_s}: Task has no defined type"
      @@ok = false
      return nil
    end
    @@status = "#{__method__.to_s}: Successfully examined task"
    @@ok = true
    return true if @type == 'time'
    return false
  end

  def complete?
    # If it's a timer task, delegate this to 'timer_complete?'.
    if self.timer?
      return self.timer_complete?
    else
      # If it's not a timer, just look at the complete flag.
      return @complete
    end
  end

  def delay?
    # One type of 'timer' task, a 'delay' task is one whose type ends in
    # 'delay'.
    unless @type
      @@status = "#{__method__.to_s}: Task has no defined type"
      @@ok = false
      return nil
    end
    @@status = "#{__method__.to_s}: Successfully examined task"
    @@ok = true
    return true if @type.to_s.end_with? 'delay'
    return false
  end

  def startable?
    # A task is "startable" if it isn't marked complete, its dependencies are
    # all met, it's not an alarm task, and it isn't marked started.
    return false if self.complete?
    return false unless self.deps_met?
    return false if self.alarm?
    return false if @started
    return true
  end

  def started?
    return true if self.alarm?
    return false unless @started
    return true
  end

  def timer?
    # A 'timer' task is either a 'delay' or an 'alarm'.
    unless @type
      @@status = "#{__method__.to_s}: Task has no defined type"
      @@ok = false
      return nil
    end
    @@status = "#{__method__.to_s}: Successfully examined task"
    @@ok = true
    return true if self.delay? or self.alarm?
    return false
  end

  def mark_complete
    @complete = true
    @failcount = nil
    @lastfail = nil
    if self.delay?
      @timestamp = Time.new
    end
    @@status = "#{__method__}: Successfully marked complete."
    @@ok = true
    return true
  end

  def mark_started
    @started = true
    @@status = "#{__method__}: Successfully marked started."
    @@ok = true
    return true
  end

  def unmark_started
    # Turn @started off. For one thing, a task that fails is unmarked started.
    @started = false
    @@status = "#{__method__}: Successfully unmarked started."
    @@ok = true
    return true
  end

  def to_s
    # Expresses the task as a string.

    out = ''
    out += "*** #{@id}\n"
    self.instance_variables.each do |var|
      next if var.nil?
      next if var == :@id
      if var == :@deps
        next if @deps.size == 0
        out += "  deps =>\n"
        @deps.each do |d|
          if d.kind_of? Task
            out += "    #{d.id}\n"
          else
            outs += "    '#{d}'\n"
          end
        end
      else
        out += "  #{var.to_s} => #{self.instance_variable_get var}\n"
      end
    end
    @@status = "#{__method__.to_s}: Task successfully expressed as string."
    @@ok = true
    return out
  end

  def print
    str = self.to_s
    print str
    if @@ok
      @@status = "#{__method__.to_s}: Task successfully printed."
    end
    return true
  end

  def timer_complete?
    unless self.timer?
      @@status = "#{__method__.to_s}: Task is not a time-delay task of any type."
      @@ok = false
      return nil
    end
    unless @param
      @@status = "#{__method__.to_s}: Task has no param value"
      @@ok = false
      return nil
    end
    @@status = "#{__method__.to_s}: Successfully examined task."
    @@ok = true
    # We just call delay_complete? or alarm_complete? as appropriate.
    if self.delay?
      return self.delay_complete?
    elsif self.alarm?
      return self.alarm_complete?
    else
      # Shouldn't happen.
      @@status = "#{__method__.to_s}: Shouldn't happen."
      @@ok = false
      return nil
    end
  end

  def timer_remaining
    unless self.timer?
      @@status = "#{__method__}: Task is not a time-delay task of any type."
      @@ok = false
      return nil
    end
    unless @param
      @@status = "#{__method__}: Task has no param value"
      @@ok = false
      return nil
    end
    @@status = "#{__method__}: Successfully examined task."
    @@ok = true
    self.timereq_autoset unless @timereq
    return @timereq
  end

  def timewait_timestamp
    # Returns a Time object that represents the real-world time represented by
    # an 'alarm-clock' task's @param. The @param is a time and timezone,
    # signifying that the task should not be run before that time on the
    # current day in that time zone. The value of @param should be "HH:MM_TZ"
    # or "HH:MM:SS_TZ", where TZ is a timezone abbreviation such as
    # "America/Indiana/Indianapolis" from the standard tzinfo table. For
    # example, @param could be "12:00_America/Los_Angeles", meaning this task
    # should not run before 12:00 in Los Angeles time today (where "today" is
    # taken to mean the day it currently is in Los Angeles).

    # What is the current UTC time?
    t_utc = Time.now.gmtime

    # Split @param into its time and timezone.
    (target_time_str, target_tz_str) = @param.split '_', 2
    target_tz = TZInfo::Timezone.get target_tz_str
    raise RuntimeError.new "Unable to find time zone '#{target_tz_str}'" unless target_tz

    # This gives us the offset in seconds between UTC and @param's
    # timezone. Add this to UTC to get the time in @param's timezone, in other
    # words. This takes DST into effect, if it is in effect right now in that
    # timezone.
    target_tz_offset = (target_tz.utc_to_local t_utc).to_i - t_utc.to_i

    # Parse @param. (Using "2000-01-01" only so Time.parse can parse the
    # string, which should be a time only.)
    t_target_time_only = Time.parse "2000-01-01T#{target_time_str}"
    # The Time object 't_target_time_only' now contains the hour, minute, and second
    # for @param in a way that can be easily worked with using the Time
    # object's methods. The year/month/day in t_param is obviously 2000-01-01,
    # which is meaningless in this context.

    # The question now is what date it currently is in @param's time
    # zone. Fortunately this isn't hard.
    t_target_now = t_utc.getlocal target_tz_offset

    # Take the date portion of target_datetime and add target_time to that.
    task_datetime = Time.new t_target_now.year,
                             t_target_now.month,
                             t_target_now.day,
                             t_target_time_only.hour,
                             t_target_time_only.min,
                             t_target_time_only.sec,
                             target_tz_offset

    # That is what we want. Return it.
    return task_datetime
  end

  def timewait_complete?
    unless self.timer?
      @@status = "#{__method__.to_s}: Task is not a timer"
      @@ok = false
      return nil
    end
    unless @param
      @@status = "#{__method__.to_s}: Value of @param is undefined"
      @@ok = false
      return nil
    end
    t_now = Time.now
    t_target = self.timewait_timestamp
    return nil unless t_target
    return t_now >= t_target
  end

  def timereq_autoset time = nil
    # Automatically sets a time-based task's timereq (estimated time required
    # to complete). If the task is of type 'time', sets timereq based on the
    # time in the @param attribute and the current time (if the time parameter
    # is given to this method, uses that instead of the current time). If the
    # task if of type '*delay', sets timereq based on the 'param' attribute --
    # unless the 'timestamp' attribute is set, in which case it uses that value
    # and the current time (or the time parameter, if given). If the task isn't
    # of either of those types, calling this results in error messages being
    # set and a return value of nil.

    unless @type
      @@status = "#{__method__.to_s}: Task has no type defined"
      @@ok = false
      return nil
    end
    unless self.timer?
      @@status = "#{__method__.to_s}: Task is not a time-based delay"
      @@ok = false
      return nil
    end
    unless @param
      @@status = "#{__method__.to_s}: Task has no param defined"
      @@ok = false
      return nil
    end
    time ||= Time.now
    timereq = nil
    if @type == 'time'
      timereq = self.timewait_timestamp - time
    elsif self.delay?
      if @timestamp
        timereq = @timestamp - time
      else
        timereq = @param
      end
    else
      raise RuntimeError.new "Shouldn't happen"
    end
    if timereq
      timereq = 0 if timereq < 0
      @timereq = timereq
      return true
    else
      return false
    end
  end

  def seconds_since_fail
    # Returns the time in seconds (floating-point) since the last failure. If
    # the task has not failed (i.e. it is marked complete, or has a zero
    # failcount), the result is nil.
    return nil if @complete
    return nil if @failcount.zero? or @lastfail.nil?
    return Time.now - @lastfail
  end

  def status
    return @@status
  end

  def ok?
    return @@ok
  end
end
