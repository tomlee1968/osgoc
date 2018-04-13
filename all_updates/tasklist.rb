require 'forwardable'
require './task'
require 'yaml'

class TaskList

  extend Forwardable

  def_delegators :@tasks, :each, :length, :size

  def initialize arg = {}
#    [:tasks].each do |attr|
#      next unless arg.key? attr
#      self.instance_variable_set attr, arg[attr]
#    end
    if arg.key? :tasks
      tasks = arg[:tasks]
    else
      @tasks = Set.new
    end
    @@status = "TaskList.new: TaskList object successfully defined"
    @@ok = true
  end

  def tasks= new_tasks
    if new_tasks.kind_of? Array
      @tasks = Set.new new_tasks
    elsif new_tasks.kind_of? Set
      @tasks = new_tasks
    else
      raise "#{__method__}: Attempted to set task list to a #{new_tasks.class}."
    end
  end

  def tasks
    # Returns @tasks as an array.

    return @tasks.to_a
  end

  def map(&block)
    return @tasks.to_a.map &block
  end

  def select(&block)
    return @tasks.to_a.select &block
  end

  def sort(&block)
    return @tasks.to_a.sort &block
  end

  def push t
    @tasks.add t
  end

  def add *args
    count = 0
    args.each do |arg|
      if arg.kind_of? Array
        arg.each do |a|
          count += self.add a
        end
      elsif arg.kind_of? Task
        @tasks.add arg
        count += 1
      end
    end
    @@status = "#{__method__}: #{count} tasks added."
    @@ok = count > 0
    return count
  end

  def create_and_add arg
    t = Task.new arg
    unless t
      @@status = "#{__method__}: Problem creating task (#{t.status})"
      @@ok = false
      return nil
    end
    if self.add t
      return t
    else
      return nil
    end
  end

  def write path = nil
    unless path
      @@status = "#{__method__}: File path undefined"
      @@ok = false
      return nil
    end
    if File.write path, (YAML.dump self)
      @@status = "#{__method__}: Saved successfully"
      @@ok = true
      return true
    else
      @@status = "#{__method__}: Error while saving: #{$@}"
      @@ok = false
      return nil
    end
  end

  def undone
    undone = self.select { |t| !t.complete? }
    @@status = "#{__method__.to_s}: Successfully searched for undone tasks"
    @@ok = true
    return undone
  end

  def doable
    # Returns a list of doable tasks, meaning tasks not marked complete whose
    # dependencies are all met.
    doable = self.select { |t| !t.complete and t.deps_met? }
    @@status = "#{__method__.to_s}: Successfully searched for doable tasks"
    @@ok = true
    return doable
  end

  def find_task_by_id id
    # Searches the tasklist for a task with the given id. Returns nil if not
    # found. Raises an exception if there is more than one task with the given
    # id, as that's not supposed to happen.

    m = self.select { |t| t.id == id }
    return nil if m.size == 0
    if m.size > 1
      raise RuntimeError.new "Tasklist has more than one task with id '#{id}'"
    end
    return m.first
  end

  def dep_ids_to_tasks
    # Goes through the dependencies of every task in @tasks, and if it finds a
    # string instead of a Task, it will look for the task with that string as
    # an ID and replace the string with the Task. This allows a calling program
    # to name not-yet-created tasks as dependencies and call this method once
    # all Tasks are created.

    speedcache = {}
    @tasks.each do |t|
      newdeps = Set.new
      t.deps.each do |dep|
        if dep.kind_of? Task
          newdeps.add dep
        elsif dep.kind_of? String
          if speedcache.key? dep
            newdeps.add speedcache[dep]
          else
            begin
              match = self.find_task_by_id dep
            rescue RuntimeError => err
              raise RuntimeError.new "Task '#{t.id}' contains a dependency on id '#{dep}', which matches more than one task: #{err.to_s}"
            end
            if match.nil?
              raise RuntimeError.new "Task '#{t.id}' contains a dependency on id '#{dep}', which doesn't exist"
            end
            speedcache[dep] = match
            newdeps.add match
          end
        else
          raise RuntimeError.new "Found a '#{dep.class}' in dependency list of task '#{dep.id}'"
        end
      end
      t.deps = newdeps
    end
    @@status = "#{__method__.to_s}: Converted dependency IDs to Tasks without problems"
    @@ok = true
    return true
  end

  def follow_deps t, stack, blocked
    # Recursively follow the dependencies of the given task, keeping track of
    # the stack of task dependencies that got us here and the hash of blocked
    # tasks (ones already checked and found OK, so there's no need to check
    # them again).

#    @@status += "entering follow_deps: #{t.id}; #{stack.join ', '}; #{blocked.keys.join ', '}\n"
    return nil if blocked.key? t.id and blocked[t.id]
    return stack if stack.include? t.id
    extend_stack = stack + [t.id]
    t.deps.each do |d|
      next unless d.kind_of? Task
      return follow_deps d, extend_stack, blocked
    end
    return nil
  end

  def find_cycles
    # Find a cyclic dependency if one exists. We are not trying to find all of
    # them, just determine whether one exists.

    @@status = ''
    blocked = {}
    @tasks.each do |t|
      next unless t.kind_of? Task
      next if blocked.key? t.id and blocked[t.id]
      stack = follow_deps t, [], blocked
      if stack
        @@status = "#{__method__}: Cyclic dependency found starting with '#{t.id}': #{stack.join ', '}"
        @@ok = false
        return true
      end
      blocked[t.id] = true
    end
    @@status = "#{__method__}: No cyclic dependencies found."
    @@ok = true
    return false
  end

  def check
    any_incompletes_left = true
    while any_incompletes_left
      any_incompletes_left = false
      doable = []
      @tasks.each do |t|
        next if t.complete? or (t.has_deps? and !t.deps_met?)
        any_incompletes_left = true
        doable.push t
      end
    end
    doable.each do |t|
      t.mark_complete
    end
  end

  def status
    return @@status
  end

  def ok?
    return @@ok
  end
end
