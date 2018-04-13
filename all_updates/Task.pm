package Task;

use strict;
use warnings;
use Date::Calc qw(:all);
use Date::Parse;
use Time::Local;

$Task::VERSION = '1.0';
$Task::STATUSMSG = 'Initializing';
$Task::STATUS = 1;

=head1 NAME

Task - Utility module for handling OS update tasks

=head1 SYNOPSIS

This module creates a Task class; Task objects represent information about
specific OS update tasks.  Primarily the only code that uses this object class
is the all_updates.pl script.  Task objects have methods for setting, querying
and incrementing various properties of a task and for useful operations such as
declaring a task complete.  More importantly, there are numerous tests and
error checks to help catch problems.

=head1 DESCRIPTION

A script creates a new Task object with the Task->new subroutine as usual,
using key => value notation as with a Perl hash literal to define the object's
properties.  Example:

use Task;
my $task = Task->new(host => $hostname,
                     type => "osupdate",
                     id => "$hostname/osupdate",
                     cmd => "/opt/sbin/osupdate");

Every Task object has an "id" -- a unique identifier that is usually equal to
"host/type", where "host" is the host on which the OS update task is to be
performed and "type" is the type of task to perform.  The reason why this is
unique is that the same type of task should not be performed on the same host
more than once in a given update cycle.

Some types of task are special and have methods to assist in using them.  One
of these special types are timer tasks, which are meant to keep track of time.
Timer tasks are divided into two types: delay tasks and alarm-clock tasks.
Delay tasks are meant to delay for a given amount of time once started, so
is_complete() won't be true until that time has elapsed.  Alarm-clock tasks are
meant to delay until a given clock time on the current day, so is_complete()
won't return true until that given time has arrived.

To create a delay task:

my $delay = Task->new(host => 'myhost',
                      type => 'foo_delay',
                      id => 'myhost/foo_delay',
                      cmd => 'blahblahdelaything',
                      param => '120');

To start the delay timer:

$delay->delay_start();

To test whether the delay timer is running:

if($delay->is_started()) {
    print "Delay timer running\n";
} else {
    print "Delay timer not yet started\n";
}

To test whether the delay timer is complete:

if($delay->is_complete()) {
    print "Delay timer is finished\n";
} else {
    print "Delay timer not yet finished\n";
}

To create an alarm-clock task:

my $clock = Task->new(host => 'myhost',
                      type => 'dstime',
                      id => 'myhost/dstime',
                      cmd => 'sometimething',
                      param => '12:00-05');

To test whether it's that time yet, just use is_complete().  There is no need
to start an alarm-clock task as with a delay task; is_started() always returns
true for them.  Their type can be either 'time' or 'dstime', the difference
being that 'dstime' tasks take Daylight-Saving Time and other such date-based
timekeeping contrivances into account, while 'time' tasks don't (if you live in
a part of the world where no such practice occurs, or if the literal real-world
wall-clock time doesn't matter to your task).

The variable $Task::VERSION will always contain the version of this module.

The variable $Task::STATUSMSG will always contain a human-readable string
indicating the status as of the last method call.

The variable $Task::STATUS will be a machine-testable status value as of the
last method call; a true value indicates a success or OK status, while a false
value indicates that some sort of error has occurred.

=head1 FUNCTIONS

=over 4

=cut

sub objtest($) {
  #
  # Utility routine to make sure that the given thing is really a Task object
  #
  # Call example:
  # return undef unless Task::objtest $self;
  #
  my($self) = @_;
  unless(defined($self)) {
    $Task::STATUSMSG = "Object undefined";
    $Task::STATUS = '';
    return undef;
  }
  unless(ref($self) and ref($self) eq 'Task') {
    $Task::STATUSMSG = "Object not of type Task";
    $Task::STATUS = '';
    return undef;
  }
  return 1;
}

=item Task->new(id => 'task_id',
                host => 'hostname',
                cmd => 'cmd',
                param => 'value',
                type => 'tasktype',
                ...)

Defines a new Task object as used by all_updates.pl.  Give keys and values in
the form of hash entries.  The "id" key is required.  Available keys include:

=over 4

=item id: A unique identifier for the task

=item type: A type string for the task

=item host: The host on which the task is to be done

=item cmd: The command to execute, or an identifier for the pseudo-command

=item param: A parameter, usually for a pseudo-command

=item cmdsudo: A flag indicating whether the command requires sudo or not

=item timereq: An estimate of the time in seconds required by the task

=item complete: A flag indicating whether the task is complete or not

=item started: A flag indicating whether the task has been started yet

=item failcount: A counter of the number of failed attempts to perform cmd

=item lastattempt: The timestamp of the last attempt

=item lastfail: The timestamp of the last failed attempt

=item timestamp: A timestamp used for delay tasks

=item skip: A flag indicating that the task is to be temporarily skipped

=item manual: A flag indicating that the user reported the task manually done

=item tmux_window: The identifier of the tmux window used to perform the task

=item waitforothers: A flag indicating that when processing lists of tasks,
scripts should postpone starting this task until all startable tasks with other
types have been completed

=item dep: A list (in the form of a reference to an array) of either references
to other Task objects representing tasks this one depends on, or the values of
their 'id' properties

=back

If there is an error, such as if a key is given an undefined value or the 'dep'
key doesn't point to an array reference, this subroutine returns undef and sets
$Task::STATUSMSG and $Task::STATUS.

=cut

sub new($$) {
  my($class, %data) = @_;
  my $self = {};

  foreach my $key (qw(id type host cmd param cmdsudo timereq complete started
		      failcount lastattempt lastfail timestamp skip manual
		      tmux_window waitforothers dep)) {
    next unless exists $data{$key};
    unless(defined($data{$key})) {
      $Task::STATUSMSG = "Task->new: Key '$key' points to an undefined value";
      $Task::STATUS = '';
      return undef;
    }
    if($key eq 'dep') {
      unless(ref($data{$key}) and ref($data{$key}) eq 'ARRAY') {
	$Task::STATUSMSG = "Task->new: Key 'dep' does not point to an array reference";
	$Task::STATUS = '';
	return undef;
      }
    }
    $self->{$key} = $data{$key};
  }
  $Task::STATUSMSG = "Task->new: Task object successfully defined";
  $Task::STATUS = 1;
  return bless $self, $class;
}

=item $t->alarm_is_complete()

If the task is of type 'time' or 'dstime', this method can help process it.
This returns true if the task's appointed time has been reached and false if
not.  If the task isn't of one of those types, returns undef.

=cut

sub alarm_is_complete($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  unless($self->is_alarm()) {
    $Task::STATUSMSG = "alarm_is_complete: Task is not an alarm clock.";
    $Task::STATUS = '';
    return undef;
  }
  unless($self->{param}) {
    $Task::STATUSMSG = "alarm_is_complete: Task has no param value";
    $Task::STATUS = '';
    return undef;
  }
  $Task::STATUSMSG = "alarm_is_complete: Successfully examined task.";
  $Task::STATUS = 1;
  # If the task is already marked complete, go no further.
  if($self->complete_get) {
    return 1;
  }
  my $timewait_return = undef;
  if($self->{type} eq 'time') {
    $timewait_return = $self->timewait_is_complete;
  } elsif($self->{type} eq 'dstime') {
    $timewait_return = $self->dstimewait_is_complete;
  } else {
    # Shouldn't happen.
    warn("Alarm is neither time nor dstime -- shouldn't happen");
    $self->print();
    return undef;
  }
  if($timewait_return) {
    $self->mark_complete;
  }
  return $timewait_return;
}

=item $t->cmd_get()

Returns the 'cmd' property for a task.  Typically this is the command to be
issued remotely to the host, but it may instead be a pseudocommand to tell the
update script to do something (such as delay for a given amount of time) at
some step in the update process.  As with all property retrieval methods, if
there's an error of some sort, this method will return undef and set
$Task::STATUSMSG and $Task::STATUS.

=cut

sub cmd_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('cmd');
}

=item $t->cmd_has()

Returns true if a task has a command set, false otherwise.

=cut

sub cmd_has($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->has_property('cmd');
}

=item $t->cmd_set($cmd)

Sets the command for a task (a string).

=cut

sub cmd_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('cmd', $arg);
}

=item $t->cmdsudo_get()

Returns the cmdsudo flag for a task.

=cut

sub cmdsudo_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('cmdsudo');
}

=item $t->cmdsudo_set($cmd)

Sets the cmdsudo flag for a task.

=cut

sub cmdsudo_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('cmdsudo', $arg);
}

=item $t->complete_get()

Returns the complete flag for a task.

=cut

sub complete_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('complete');
}

=item $t->complete_set($cmd)

Sets the complete flag for a task.

=cut

sub complete_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('complete', $arg);
}

=item $t->delay_is_complete()

If the type of task $t is '*delay', this method and delay_start can help
process it.  This method returns true if the delay timer started with
delay_start is up and false otherwise.  If $t isn't of type '*delay' or has no
'param' value set, or if delay_start hasn't been called to start the timer,
returns undef.  This doesn't work for 'time' or 'dstime' tasks.

=cut

sub delay_is_complete($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  unless($self->{type} and $self->is_delay()) {
    $Task::STATUSMSG = sprintf "delay_is_complete: Task is not of type '*delay' ('%s' instead)", $self->{type} || '(undef)';
    $Task::STATUS = '';
    return undef;
  }
  unless($self->{param}) {
    $Task::STATUSMSG = "delay_is_complete: Delay task has no param value";
    $Task::STATUS = '';
    return undef;
  }
  # If the complete flag has been set, don't test any further.  Make it look as
  # if the timer has been completed (and started, if necessary).
  if($self->complete_get) {
    $Task::STATUSMSG = "delay_is_complete: Successfully tested delay timer";
    $Task::STATUS = 1;
    $self->{timestamp} = time unless $self->{timestamp} and time >= $self->{timestamp};
    return 1;
  }
  unless($self->{timestamp}) {
    $Task::STATUSMSG = "delay_is_complete: Timer has not been started";
    $Task::STATUS = '';
    return undef;
  }
  $Task::STATUSMSG = "delay_is_complete: Successfully tested delay timer";
  $Task::STATUS = 1;
  if(time >= $self->{timestamp}) {
    $self->mark_complete;
    return 1;
  } else {
    return '';
  }
}

=item $t->delay_start()

If the type of task $t is '*delay', this method and delay_is_complete can help
process it.  Call this method to start a delay timer for 'param' seconds (first
using param_set to set the value of 'param').  If a timer is already running
for this task, calling this method again will forget the existing one and
restart the timer.  Returns true on success.  If $t isn't of type '*delay' or
has no 'param' value set, returns undef.  This doesn't work for 'time' or
'dstime' tasks.

=cut

sub delay_start($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  unless($self->{type} and $self->{type} =~ /delay$/) {
    $Task::STATUSMSG = sprintf "delay_start: Task is not of type '*delay' ('%s')", $self->{type} || '(undef)';
    $Task::STATUS = '';
    return undef;
  }
  unless($self->{param}) {
    $Task::STATUSMSG = "delay_start: Delay task has no param value";
    $Task::STATUS = '';
    return undef;
  }
  $self->{timestamp} = time + $self->{param};
  $self->mark_started();
  return 1;
}

=item $t->dep_add(list of $tasks or $ids)

Adds one or more tasks to the task's list of dependencies.  Can specify Task
objects or task ID strings.  If any of the items is undefined, nothing happens
and returns undef.

=cut

sub dep_add($@) {
  my($self, @args) = @_;
  return undef unless Task::objtest $self;
  unless(exists $self->{dep}
	 and defined $self->{dep}
	 and ref($self->{dep})
	 and ref($self->{dep}) eq 'ARRAY') {
    $Task::STATUSMSG = "dep_add: Task object's 'dep' property was not an array reference; this was corrected";
    $Task::STATUS = '';
    $self->{dep} = [];
  }
  foreach my $item (@args) {
    unless(defined $item) {
      $Task::STATUSMSG = "dep_add: Attempted to add undefined value to Task object's 'dep' array";
      $Task::STATUS = '';
      return undef;
    }
  }
  push @{$self->{dep}}, @args;
  $Task::STATUSMSG = "dep_add: Items successfully added to Task object's 'dep' array";
  $Task::STATUS = 1;
  return 1;
}

=item $t->dep_get()

Returns the task's list of dependencies.

=cut

sub dep_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('dep');
}

=item $t->dep_get_unmet()

Returns a list of the task's unmet dependencies.

=cut

sub dep_get_unmet($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return [ grep { !$_->is_complete() } @{$self->get_property('dep')} ];
}

=item $t->dep_grep({ code })

Searches through a task's dependencies for values for which the given code
fragment evaluates to true.  Returns an array of the matching dependencies.
Returns an empty array if there are no matches.  Returns undef if there is an
error.

=cut

sub dep_grep($$) {
  my($self, $code) = @_;
  return undef unless Task::objtest $self;
  if(ref($code) ne 'CODE') {
    $Task::STATUSMSG = "dep_grep: Argument is not a CODE reference";
    $Task::STATUS = '';
    return undef;
  }
  unless(exists $self->{dep}
	 and defined $self->{dep}
	 and ref($self->{dep})
	 and ref($self->{dep}) eq 'ARRAY') {
    $Task::STATUSMSG = "dep_grep: Task object's 'dep' property was not an array reference; this was corrected";
    $Task::STATUS = '';
    $self->{dep} = [];
  }
  my @matchers = grep { &$code } @{$self->{dep}};
  $Task::STATUSMSG = "dep_grep: Dependency array searched";
  $Task::STATUS = 1;
  return @matchers;
}

=item $t->dep_has()

Returns true if the task has dependencies, false otherwise.

=cut

sub dep_has($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->has_property('dep');
}

=item $t->dep_met($cmd)

Returns true or false based on whether the given task's dependencies are met.
Returns true if the task has no dependencies (its dependencies are trivially
met).  Returns undef if any dependencies aren't Task objects or some other
error occurs.

=cut

sub dep_met($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  unless(exists $self->{dep}
	 and defined $self->{dep}
	 and ref($self->{dep})
	 and ref($self->{dep}) eq 'ARRAY') {
    $Task::STATUSMSG = "dep_met: Task object's 'dep' property was not an array reference; this was corrected";
    $Task::STATUS = '';
    $self->{dep} = [];
  }
  # Return true if no dependencies.
  return 1 unless $self->dep_has();
  $Task::STATUSMSG = "dep_met: Dependencies successfully tested.";
  $Task::STATUS = 1;
  # If even one dependency is unmet, return false.
  foreach my $dep (@{$self->{dep}}) {
    unless(ref($dep) eq 'Task') {
      $Task::STATUSMSG = sprintf "dep_met: %s has a dependency that is not a Task", $self->{id};
      $Task::STATUS = '';
      return undef;
    }
    return '' unless $dep->is_complete();
  }
  # If we're still here, all dependencies were met.
  return 1;
}

=item $t->dep_set($cmd)

Sets the dependency list for a task.

=cut

sub dep_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('dep', $arg);
}

=item $t->failcount_get()

Returns the failure count for a task.

=cut

sub failcount_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('failcount');
}

=item $t->failcount_inc([$inc])

Increments the failure count for a task by $inc (default 1).

=cut

sub failcount_inc($;$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->inc_property('failcount', $arg);
}

=item $t->failcount_set($cmd)

Sets the failure count for a task.

=cut

sub failcount_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('failcount', $arg);
}

=item $t->host_get()

Returns the host for a task.

=cut

sub host_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('host');
}

=item $t->host_has()

Returns true if the task's host is defined, false otherwise.

=cut

sub host_has($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->has_property('host');
}

=item $t->host_set($cmd)

Sets the host for a task (a string).

=cut

sub host_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('host', $arg);
}

=item $t->id_get()

Returns the ID for a task.

=cut

sub id_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('id');
}

=item $t->id_set($cmd)

Sets the ID for a task (a string).

=cut

sub id_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('id', $arg);
}

=item $t->is_alarm()

Returns true if the task is an alarm-clock task (i.e. its type is 'time' or
'dstime').  Returns false if not.

=cut

sub is_alarm($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  unless($self->{type}) {
    $Task::STATUSMSG = "is_alarm: Task has no defined type";
    $Task::STATUS = '';
    return undef;
  }
  $Task::STATUSMSG = "is_alarm: Successfully examined task";
  $Task::STATUS = 1;
  return 1 if $self->{type} eq 'time'
    or $self->{type} eq 'dstime';
  return '';
}

=item $t->is_complete()

Returns true if the task is complete, false otherwise.  Basically a synonym of
complete_get(), except in the case that the task is a time-based delay of some
sort, in which case it calls timer_is_complete() (although if it's an alarm and
the 'complete' flag is set true, that overrides timer_is_complete to force it
true, since that flag is not otherwise used for alarms and there is no other
way to force alarms to be treated as complete).

=cut

sub is_complete($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  # If it's a timer task, delegate this to timer_is_complete.
  if($self->is_timer()) {
    return $self->timer_is_complete();
  } else {
    # If it's not a timer, just look at the complete flag.
    return $self->complete_get();
  }
}

=item $t->is_delay()

Returns true if the task is a delay (i.e. its type is '*delay').  Returns false
if not.

=cut

sub is_delay($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  unless($self->{type}) {
    $Task::STATUSMSG = "is_delay: Task has no defined type";
    $Task::STATUS = '';
    return undef;
  }
  $Task::STATUSMSG = "is_delay: Successfully examined task";
  $Task::STATUS = 1;
  return 1 if $self->{type} =~ /delay$/;
  return '';
}

=item $t->is_startable()

Returns true if the task is startable -- that is, it's not marked complete, its
dependencies are met, and it's not marked already started.  Returns false
otherwise.

Although is_complete() and is_started() work normally for '*delay' tasks, 'time'
and 'dstime' tasks work differently.  is_started() always returns true for them,
although is_complete() works normally.

=cut

sub is_startable($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return '' if $self->is_complete();
  return '' unless $self->dep_met;
  return '' if $self->is_alarm();
  return '' if $self->is_started();
  return 1;
}

=item $t->is_started()

Returns true if the task is marked started.  Note that alarm-clock tasks (type
'time' and 'dstime') are always considered to be started.

=cut

sub is_started($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return 1 if $self->is_alarm();
  return '' unless $self->started_get();
  return 1;
}

=item $t->is_timer()

Returns true if the task is a time-based delay (i.e. its type is '*delay',
'time', or 'dstime').  Returns false if not.

=cut

sub is_timer($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  unless($self->{type}) {
    $Task::STATUSMSG = "is_timer: Task has no defined type";
    $Task::STATUS = '';
    return undef;
  }
  $Task::STATUSMSG = "is_timer: Successfully examined task";
  $Task::STATUS = 1;
  return 1 if $self->is_delay()
    or $self->is_alarm();
  return '';
}

=item $t->is_waitforothers()

Returns true if the task is marked "waitforothers", meaning that scripts
executing a list of tasks should process all other available tasks before this
one if possible.

=cut

sub is_waitforothers($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return 1 if $self->waitforothers_get();
  return '';
}

=item $t->lastattempt_get()

Returns the last attempt timestamp for a task.

=cut

sub lastattempt_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('lastattempt');
}

=item $t->lastattempt_set($cmd)

Sets the last attempt timestamp for a task.

=cut

sub lastattempt_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('lastattempt', $arg);
}

=item $t->lastfail_get()

Returns the last failure timestamp for a task.

=cut

sub lastfail_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('lastfail');
}

=item $t->lastfail_set($cmd)

Sets the last failure timestamp for a task.

=cut

sub lastfail_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('lastfail', $arg);
}

=item $t->manual_get()

Returns the manual flag for a task.

=cut

sub manual_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('manual');
}

=item $t->manual_set($cmd)

Sets the manual flag for a task.

=cut

sub manual_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('manual', $arg);
}

=item $t->mark_complete()

Marks the task complete and unsets the failure counter and last failure
timestamp.

=cut

sub mark_complete($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  $self->{complete} = 1;
  delete $self->{failcount};
  delete $self->{lastfail};
  if($self->is_delay()) {
    $self->{timestamp} = time();
  }
  $Task::STATUSMSG = 'Task successfully marked complete.';
  $Task::STATUS = 1;
  return 1;
}

=item $t->mark_started()

Marks the task as started.

=cut

sub mark_started($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  $self->{started} = 1;
  $Task::STATUSMSG = 'Task successfully marked started.';
  $Task::STATUS = 1;
  return 1;
}

=item $t->param_get()

Returns the parameter for a task's command.

=cut

sub param_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('param');
}

=item $t->param_inc($inc)

Increments the parameter for a task's command by $inc.

=cut

sub param_inc($;$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->inc_property('param', $arg);
}

=item $t->param_set($param)

Sets the parameter for a task's command.

=cut

sub param_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('param', $arg);
}

=item $t->print()

Print the task.

=cut

sub print($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  printf "*** %s\n", $self->{id};
  foreach my $key (sort keys %$self) {
    next unless $self->{$key};
    next if $key eq 'id';
    if($key eq 'dep') {
      next unless $#{$self->{dep}} > -1;
      print "  dep =>\n";
      foreach my $dep (@{$self->{dep}}) {
	if(ref($dep)) {
	  printf "    %s*\n", $dep->{id};
	} else {
	  printf "    %s\n", $dep;
	}
      }
    } else {
      printf "  %s => %s\n", $key, $self->{$key};
    }
  }
  $Task::STATUSMSG = "Task successfully printed.";
  $Task::STATUS = 1;
  return 1;
}

=item $t->skip_get()

Returns the skip flag for a task.

=cut

sub skip_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('skip');
}

=item $t->skip_set($cmd)

Sets the skip flag for a task.

=cut

sub skip_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('skip', $arg);
}

=item $t->skip_unset()

Removes the skip flag for a task.

=cut

sub skip_unset($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->unset_property('skip');
}

=item $t->started_get()

Returns the started flag for a task.

=cut

sub started_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('started');
}

=item $t->started_set($cmd)

Sets the started flag for a task.

=cut

sub started_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('started', $arg);
}

=item $t->timer_is_complete()

If the task is of type '*delay', 'time' or 'dstime', this method can help
process it.  This returns true if the task's appointed time has been reached
and false if not.  If the task isn't of one of those types, or if it's a
'*delay' that hasn't even been started yet, returns undef.

=cut

sub timer_is_complete($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  unless($self->is_timer()) {
    $Task::STATUSMSG = "timer_is_complete: Task is not a time-delay task of any type.";
    $Task::STATUS = '';
    return undef;
  }
  unless($self->{param}) {
    $Task::STATUSMSG = "timer_is_complete: Task has no param value";
    $Task::STATUS = '';
    return undef;
  }
  $Task::STATUSMSG = "timer_is_complete: Successfully examined task.";
  $Task::STATUS = 1;
  # We just call delay_is_complete or alarm_is_complete as appropriate.
  if($self->is_delay()) {
    return $self->delay_is_complete();
  } elsif($self->is_alarm()) {
    return $self->alarm_is_complete();
  } else {
    # Shouldn't happen.
    warn("Shouldn't happen");
    $self->print();
    return undef;
  }
}

=item $t->timer_remaining()

If the task is of type '*delay', 'time' or 'dstime', this method can help
process it.  This returns the number of seconds remaining until the time-based
delay completes.  Returns undef if the task isn't one of those types, if the
task is malformed (such as if it doesn't have a 'param' attribute), or if we
couldn't determine the time remaining for some other reason.

=cut

sub timer_remaining($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  unless($self->is_timer()) {
    $Task::STATUSMSG = "timer_remaining: Task is not a time-based delay of any type.";
    $Task::STATUS = '';
    return undef;
  }
  unless($self->{param}) {
    $Task::STATUSMSG = "timer_remaining: Task has no param value";
    $Task::STATUS = '';
    return undef;
  }
  $Task::STATUSMSG = "timer_remaining: Successfully examined task.";
  $Task::STATUS = 1;
  $self->timereq_autoset() unless $self->{timereq};
  return $self->{timereq};
}

=item $t->timereq_get()

Returns the task's timereq.

=cut

sub timereq_get($) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('timereq');
}

=item $t->timereq_has()

Returns true if a task has a timereq set, false otherwise.

=cut

sub timereq_has($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->has_property('timereq');
}

=item $t->timereq_inc($inc)

Increments the task's timereq by $inc.

=cut

sub timereq_inc($;$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->inc_property('timereq', $arg);
}

=item $t->timereq_set($timereq)

Sets the task's timereq.

=cut

sub timereq_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('timereq', $arg);
}

=item $t->timestamp_get()

Returns the task's timestamp.

=cut

sub timestamp_get($) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('timestamp');
}

=item $t->timestamp_has()

Returns true if a task has a timestamp set, false otherwise.

=cut

sub timestamp_has($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->has_property('timestamp');
}

=item $t->timestamp_set($timestamp)

Sets the task's timestamp.

=cut

sub timestamp_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('timestamp', $arg);
}

=item $t->tmux_window_get()

Returns the tmux window for a task.

=cut

sub tmux_window_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('tmux_window');
}

=item $t->tmux_window_has()

Returns true if the task has a tmux window defined, and false if not.

=cut

sub tmux_window_has($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->has_property('tmux_window');
}

=item $t->tmux_window_set($cmd)

Sets the tmux window for a task.

=cut

sub tmux_window_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('tmux_window', $arg);
}

=item $t->tmux_window_unset($cmd)

Removes the tmux window record for a task.

=cut

sub tmux_window_unset($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->unset_property('tmux_window');
}

=item $t->type_get()

Returns the type for a task.

=cut

sub type_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('type');
}

=item $t->type_set($cmd)

Sets the type for a task (a string).

=cut

sub type_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('type', $arg);
}

=item $t->waitforothers_get()

Returns the waitforothers flag for a task.

=cut

sub waitforothers_get($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  return $self->get_property('waitforothers');
}

=item $t->waitforothers_set($cmd)

Sets the waitforothers flag for a task.

=cut

sub waitforothers_set($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  return $self->set_property('waitforothers', $arg);
}

=item $t->get_property($property)

This generic method returns the value of the given property; the various *_get
convenience methods call it.  It returns undef if $property is undefined, if
property $property does not exist, or (obviously) if property $property has
value undef.  In the case that $property is 'dep', will always return an array
reference, an empty one at the very least.

=cut

sub get_property($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  unless(defined $arg) {
    $Task::STATUSMSG = "get_property: Property argument undefined";
    $Task::STATUS = '';
    return undef;
  }
  my $origsub = (caller 1)[3] || (caller 0)[3];
  if($arg eq 'dep') {
    unless(exists $self->{dep}) {
      $Task::STATUSMSG = "$origsub: Task object's 'dep' property doesn't exist; returning []";
      $Task::STATUS = 1;
      return [];
    }
    unless(defined $self->{dep}) {
      $Task::STATUSMSG = "$origsub: Task object's 'dep' property is undef; returning []";
      $Task::STATUS = 1;
      return [];
    }
    unless(ref($self->{dep}) and ref($self->{dep}) eq 'ARRAY') {
      $Task::STATUSMSG = "$origsub: Task object's 'dep' property is not an array reference; returning []";
      $Task::STATUS = 1;
      return [];
    }
    $Task::STATUSMSG = "$origsub: Property 'dep' successfully accessed";
    $Task::STATUS = 1;
    return $self->{dep};
  }
  unless(exists $self->{$arg}) {
    $Task::STATUSMSG = "$origsub: Task object has no defined '$arg' property";
    $Task::STATUS = '';
    return undef;
  }
  $Task::STATUSMSG = "$origsub: Property '$arg' successfully accessed";
  $Task::STATUS = 1;
  return $self->{$arg};
}

=item $t->has_property($property)

This generic method returns a Perl true value (specifically 1) if the given
property exists, is defined, and has a true value.  It returns false ('', which
is false in Perl) if not.  It returns undef if $property itself is undefined.
If $property is 'dep', also returns false if the 'dep' array reference contains
zero items.

=cut

sub has_property($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  unless(defined $arg) {
    $Task::STATUSMSG = "has_property: Property argument undefined";
    $Task::STATUS = '';
    return undef;
  }
  my $origsub = (caller 1)[3] || (caller 0)[3];
  $Task::STATUSMSG = "$origsub: Property '$arg' successfully checked";
  $Task::STATUS = 1;
  return '' unless exists $self->{$arg} and defined $self->{$arg} and $self->{$arg};
  if($arg eq 'dep') {
    return '' unless ref($self->{$arg}) and ref($self->{$arg}) eq 'ARRAY';
    return '' unless $#{$self->{$arg}} > -1;
  }
  return 1;
}

=item $t->set_property($property, $value)

This generic method sets the property named $property to value $value in Task
object $t.  It returns true if the property was successfully set.  It returns
undef if $property is undefined, or if $value is.  In the case that $property
is 'dep', it also returns undef if $value is not an array reference.

=cut

sub set_property($$$) {
  my($self, $arg, $val) = @_;
  return undef unless Task::objtest $self;
  unless(defined $arg) {
    $Task::STATUSMSG = "set_property: Property argument undefined";
    $Task::STATUS = '';
    return undef;
  }
  my $origsub = (caller 1)[3] || (caller 0)[3];
  unless(defined $val) {
    $Task::STATUSMSG = "$origsub: Value argument undefined";
    $Task::STATUS = '';
    return undef;
  }
  if($arg eq 'dep') {
    unless(ref($val) and ref($val) eq 'ARRAY') {
      $Task::STATUSMSG = "$origsub: Attempted to assign a value to property 'dep' that was not an array reference";
      $Task::STATUS = '';
      return undef;
    }
  }
  $self->{$arg} = $val;
  $Task::STATUSMSG = "$origsub: Value of property '$arg' successfully set";
  $Task::STATUS = 1;
  return 1;
}

=item $t->inc_property($property [, $value])

This generic method increments the given property by $value (default 1).  It
returns true if the operation was successful.  If $property is undefined, or
the $property property is, it returns undef.  It also returns undef if
$property is 'dep', since that must be an array reference, an unincrementable
value.

=cut

sub inc_property($$;$) {
  my($self, $arg, $val) = @_;
  return undef unless Task::objtest $self;
  unless(defined $arg) {
    $Task::STATUSMSG = "inc_property: Property argument undefined";
    $Task::STATUS = '';
    return undef;
  }
  my $origsub = (caller 1)[3] || (caller 0)[3];
  if($arg eq 'dep') {
    $Task::STATUSMSG = "$origsub: Cannot increment property 'dep', which is an array reference";
    $Task::STATUS = '';
    return undef;
  }
  $val = 1 unless defined $val;
  $self->{$arg} += $val;
  $Task::STATUSMSG = "$origsub: Property '$arg' successfully incremented";
  $Task::STATUS = 1;
  return 1;
}

=item $t->unset_property($property)

This is a generic method to unset the given property's value (deleting its key)
from Task object $t.  Returns true on success.  If $property is undefined,
returns undef.

=cut

sub unset_property($$) {
  my($self, $arg) = @_;
  return undef unless Task::objtest $self;
  unless(defined $arg) {
    $Task::STATUSMSG = "unset_property: Property argument undefined";
    $Task::STATUS = '';
    return undef;
  }
  my $origsub = (caller 1)[3] || (caller 0)[3];
  delete $self->{$arg};
  $Task::STATUSMSG = "$origsub: Property '$arg' successfully unset";
  $Task::STATUS = 1;
  return 1;
}

=item $t->timewait_timestamp($dstflag)

Returns the Unix timestamp associated with a task of type 'time' or 'dstime',
based on the value of the 'param' attribute.  The parameter $dstflag indicates
whether to take Daylight-Saving Time, British Summer Time, etc. into account in
the time zone given in the 'param' attribute (not whether it is currently in
effect; the method will check for that).  If $dstflag isn't given, its value is
assumed to be false.

The value of 'param' needs to be ISO 8601-compliant.  This means:

* Time is 24-hour and given as hh[(.f+|:?mm[(.f+|:?ss[(.f+)?])])].  This means
  that the following are acceptable:

  - 02 (this means 02:00:00)
  - 02.5 (this means 02:30:00)
  - 0230 (this also means 02:30:00)
  - 02:30 (also 02:30:00)
  - 02:30.5 (means 02:30:30)
  - 0230.5 (also means 02:30:30)
  - 02:30:30
  - 02:30:30.5
  - 023030
  - 023030.5

* With no time zone designator, local time is assumed -- but beware, because
  that means local time on the machine on which the script is run, which might
  be local time or UTC (or anything, really).

* Time zone designators follow the time immediately (no whitespace).

* A time zone designator of Z means UTC.

* Otherwise a time zone designator is a +/- followed by hours and optionally
  minutes, optionally separated by a colon.  This time signifies the time that
  would have to be added to UTC to obtain the local time (exclusive of DST).
  Examples:

  - 02:00:00Z means 02:00:00 UTC.
  - 02:00:00+00 means the same.
  - 02:00:00+0000 and 02:00:00+00:00 also mean the same.
  - 02:00:00-05 means 07:00:00 UTC.
  - 02:00:00-05:30 means 07:30:00 UTC (I'm not sure that time zone exists).
  - 02:00:00-0530 means the same (it may not exist, but it's an example).

Note that there's no sense of date in the time string in 'param', and we must
have a date in order to get a Unix timestamp.  The date this method uses is the
date in the parameter's "target" time zone.  It gets the current date/time in
UTC, translates that to the target time zone, removes the time component of
that, and replaces it with the time from the parameter.  It then translates
that back into the local time zone, converts it to a Unix timestamp, and
returns that.

=cut

sub timewait_timestamp($$) {
  # Returns the Unix timestamp associated with a '&timewait' task with a
  # parameter value of <time>.  If the current time is less than that time, the
  # task is considered incomplete.  But all this routine does is calculate the
  # timestamp.

  # The first parameter is the task hashref, but the second parameter is just a
  # flag indicating whether to take US Daylight Saving Time into account.

  # The time designator <time> is ISO 8601-compliant, which means:
  #
  # * Time is 24-hour and given as hh[(.f+|:?mm[(.f+|:?ss[(.f+)?])])] -- that
  #   means that the following are all acceptable:
  #   - 02 (this means 02:00:00)
  #   - 02.5 (this means 02:30:00)
  #   - 0230 (this also means 02:30:00)
  #   - 02:30 (also 02:30:00)
  #   - 02:30.5 (means 02:30:30)
  #   - 0230.5 (also means 02:30:30)
  #   - 02:30:30
  #   - 02:30:30.5
  #   - 023030
  #   - 023030.5
  #
  # * With no time zone designator, local time is assumed (but beware; that's
  #   local time on the machine on which the script is run, which might be the
  #   local time zone or GMT).
  #
  # * Time zone designators follow the time immediately (no spaces).
  #
  # * If the time zone designator is Z, it signifies GMT/UTC.
  #
  # * Otherwise the designator is a plus or minus sign folowed by hours and
  #   optionally minutes, optionally separated by a colon.  This time signifies
  #   the time that would have to be added to UTC to obtain the local time
  #   (exclusive of DST).  For example,
  #
  #   - 02:00:00Z means 02:00:00 UTC.
  #   - 02:00:00+00 means the same.
  #   - 02:00:00+0000 and 02:00:00+00:00 also mean the same.
  #   - 02:00:00-05 means 07:00:00 UTC.
  #   - 02:00:00-05:30 means 07:30:00 UTC; I'm not sure that time zone exists.
  #   - 02:00:00-0530 means the same; it may not exist, but it's an example.

  # Now, since the time in the parameter is only a time without any sense of
  # date, we must choose a date for it in order to get a Unix timestamp that
  # can be compared with the output of the "time" function.  We must find out
  # what day it is in the parameter's "target" time zone.  Do this by getting
  # the date/time in UTC (with gmtime), then translating to the target time
  # zone, then removing the time component of that and replace it with the time
  # from the parameter.  We now have a fully determined date and time in the
  # target time zone.  We can then translate this back to the local time zone,
  # convert it to a Unix timestamp, and return that.

  # If the $dst parameter is true, assume that US DST rules hold sway in the
  # target time zone -- if the current date/time at the target would place the
  # target under DST, spring forward.

  my($t, $dst) = @_;

  # Get local and target time zones.
  my @local_tz = Timezone;	# Gives YMDhmsd
  my $tasktime = $t->{param};
  # Get the time zone from the label. (Using "2000-01-01" only so strptime can
  # parse the string.)
  my(@parse) = strptime(sprintf('2000-01-01T%s', $tasktime));
  # $parse[6] will be the time zone in seconds from UTC.  Normalize_DHMS gives
  # Dhms but no year or month.  BTW, @parse[0..2] are seconds/minutes/hours.
  unless(defined $parse[6]) {
    warn "(WARN) Unable to determine time zone from string $tasktime\n";
    return undef;
  }
  my @target_tz = (0, 0, Normalize_DHMS(0, 0, 0, $parse[6]));

  # Get the system date/time in UTC.  Produces YMDhmsywd.
  my @utc_datetime = Gmtime();
  # Add @target_tz to that to produce the current date/time in the target timezone.
  my @target_datetime = Add_Delta_YMDHMS(@utc_datetime[0..5], @target_tz);

  # Add the date from @target_datetime to the time from @parse.
  my @task_datetime = (@target_datetime[0..2],
		       $parse[2], $parse[1], $parse[0] || 0);

  # If DST is called for, determine whether it's in effect and act accordingly.
  if($dst) {
    my $dst_in_effect;
    local %ENV;
    $ENV{TZ} = 'EST5EDT';
    my @task_datetime_tz = Timezone(Mktime(@task_datetime));
    $dst_in_effect = $task_datetime_tz[6];
    @task_datetime = Add_Delta_YMDHMS(@task_datetime, 0, 0, 0, -1, 0, 0)
      if $dst_in_effect == 1;
  }

  # @task_datetime now contains the current date in the target time zone, the
  # one from the parameter, with the target time from the parameter as well.
  # But in order to have a timestamp that we can compare, we need to translate
  # that into UTC and then localtime.

  my @utc_task_datetime = Add_Delta_YMDHMS(@task_datetime,
					   map { -1*$_ } @target_tz);

  my @local_task_datetime = Add_Delta_YMDHMS(@utc_task_datetime,
					     @local_tz[0..5]);

  # Now turn that into a Unix timestamp, and we're done.
  return Mktime(@local_task_datetime);
}

=item $t->timewait_is_complete()

Returns true if we have passed the target time in a 'time'-type task's
parameter, in the timezone in the task's parameter, on the date it is in that
timezone.  Note that this ignores Daylight-Saving Time, British Summer Time,
and other similar date-based timekeeping contrivances.  Returns false if it
isn't time yet.  Returns undef if there was an error (for example, if the
task's type isn't 'time').

=cut

sub timewait_is_complete($) {
  my($self) = @_;
  return undef unless Task::objtest $self;
  unless($self->{type} and $self->{type} eq 'time') {
    $Task::STATUSMSG = "timewait_is_complete: Type is not 'time'";
    $Task::STATUS = '';
    return undef;
  }
  unless($self->{param}) {
    $Task::STATUSMSG = "timewait_is_complete: Value of 'param' property undefined";
    $Task::STATUS = '';
    return undef;
  }
  my $now_ts = time;
  my $target_ts = timewait_timestamp $self, 0;
  return undef unless defined $target_ts;
  if($now_ts >= $target_ts) {
    return 1;
  } else {
    return '';
  }
}

=item $t->dstimewait_is_complete()

Like 'timewait_is_complete', but works only for tasks of type 'dstime' and differs
only in that it takes Daylight-Saving Time, British Summer Time, etc. into
account.  Returns true if we have passed the target time in a 'time'-type
task's parameter, in the timezone in the task's parameter, on the date it is in
that timezone.  Returns false if it isn't time yet.  Returns undef if there was
an error (for example, if the task's type isn't 'dstime').

The 'param' attribute will have a value such as '12:00-05', and in areas with
DST, that '-05' refers to the Standard Time time zone.  At times of year when
DST holds sway, that '-05' would effectively become a '-04', but the advantage
of using this method is that it takes care of that for you.  That 'param'
doesn't need to change.

=cut

sub dstimewait_is_complete($) {
  # Honestly, let's get rid of DST; it doesn't save any money or energy and
  # only causes unnecessary complication and stress.  Anyway, if the target
  # time zone is known to observe US DST rules, the param will have a value
  # such as '12:00-05', where that '-05' refers to the Standard Time time zone.
  # At times of year when DST holds sway, that '-05' will effectively become a
  # '-04', but you won't have to change the hostfile.
  my($self) = @_;
  return undef unless Task::objtest $self;
  unless($self->{type} and $self->{type} eq 'dstime') {
    $Task::STATUSMSG = "dstimewait_is_complete: Type is not 'dstime'";
    $Task::STATUS = '';
    return undef;
  }
  unless($self->{param}) {
    $Task::STATUSMSG = "dstimewait_is_complete: Value of 'param' property undefined";
    $Task::STATUS = '';
    return undef;
  }
  my $now_ts = time;
  my $target_ts = timewait_timestamp $self, 1;
  return undef unless defined $target_ts;
  if($now_ts >= $target_ts) {
    return 1;
  } else {
    return '';
  }
}

=item $t->timereq_autoset([$timestamp])

Automatically sets a time-based task's timereq (estimated time required to
complete).  If the task is of time 'time' or 'dstime', sets timereq based on
the time in the 'param' attribute and the current time (if $timestamp is given,
uses that instead of the current time).  If the task is of type '*delay', sets
timereq based on the 'param' attribute -- unless the 'timestamp' attribute is
set, in which case it uses that value and the current time (and if $timestamp
is given, uses that in place of the current time).  If the task isn't of type
'*delay', 'time', or 'dstime', calling this results in error messages being set
and a return of undef.

=cut

sub timereq_autoset($;$) {
  my($self, $ts) = @_;
  return undef unless Task::objtest $self;
  unless($self->{type}) {
    $Task::STATUSMSG = "timereq_autoset: Task has no type defined";
    $Task::STATUS = '';
    return undef;
  }
  unless($self->is_timer()) {
    $Task::STATUSMSG = "timereq_autoset: Task is not a time-based delay";
    $Task::STATUS = '';
    return undef;
  }
  unless($self->{param}) {
    $Task::STATUSMSG = "timereq_autoset: Task has no param defined";
    $Task::STATUS = '';
    return undef;
  }
  $ts = time unless defined $ts;
  my $timereq = undef;
  if($self->{type} eq 'time') {
    $timereq = (timewait_timestamp $self, 0) - $ts;
  } elsif($self->{type} eq 'dstime') {
    $timereq = (timewait_timestamp $self, 1) - $ts;
  } elsif($self->is_delay()) {
    if($self->timestamp_has) {
      $timereq = $self->{timestamp} - $ts;
    } else {
      $timereq = $self->{param};
    }
  } else {
    # This shouldn't happen.
    warn("Shouldn't happen");
    $self->print();
    return undef;
  }
  if(defined $timereq) {
    $timereq = 0 if $timereq < 0;
    $self->{timereq} = $timereq;
    return 1;
  } else {
    return '';
  }
}

sub circ2($@) {
  my($self, @path) = @_;
  return '' if $self->{circ_checked};
  my $id = $self->id_get;
  my %seen = map { ($_ => 1) } @path;
  if($seen{$id}) {
    $Task::CIRCMSG = sprintf "Circular dependency path found: %s", (join " <- ", @path, $id);
    $Task::STATUS = '';
    return 1;
  }
  push @path, $id;
  my @deps = @{$self->dep_get};
  foreach my $dep (@deps) {
    return 1 if &circ2($dep, @path);
  }
  $Task::CIRCMSG = "No circular dependencies found.";
  $Task::STATUS = 1;
  $self->{circ_checked} = 1;
  return '';
}

=item $t->circ()

Tests for circular dependencies.  Returns true if any circular dependencies are
found and false if not.

=cut

sub circ($) {
  my($self) = @_;
  return 1 if &circ2($self, ());
  return '';
}

=back

=head1 BUGS

=head1 AUTHORS

Thomas Lee <thomlee@iu.edu>

=cut

$Task::STATUSMSG = 'Initialized';
$Task::STATUS = 1;

1;
