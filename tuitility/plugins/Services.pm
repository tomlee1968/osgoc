###############################################################################
# Services mode
###############################################################################

package TUItility::Mode::Services;

TUItility::Mode->import;

our($cui, $mw);
our($initsys, %services, $saved_active_value);
our($mainlbwin, $mainlb, $maintvwin, $maintv);
our($mainstattvwin, $mainstattv);
our($edlbwin, $edlb, $runlbwin, $runlb);

sub new($$) {
  my($self, $c) = @_;
  $cui = $c;
  $mw = $c->child('mw');
  &register_plugin('services', 'Services', \&mode_enter, \&mode_exit);
  return bless {};
}

sub mode_enter {
  $mainlbwin = $mw->add
    (
     'mainlbwin',
     'Window',
     -border => 1,
     -y => 1,
     -width => $cui->width / 3,
     -titlefullwidth => 1,
     -tfg => 'blue',
     -tbg => 'white',
    );
  $mainlb = $mainlbwin->add
    (
     'mainlb',
     'Listbox',
     -vscrollbar => 1,
     -onchange => \&service_selected,
     -onselchange => \&highlight_changed,
     -values => ['Gathering data ...'],
    );
  $maintvwin = $mw->add
    (
     'maintvwin',
     'Window',
     -border => 1,
     -x => $mainlbwin->width,
     -y => 1,
     -height => 8,
     -title => 'Service Info',
     -titlefullwidth => 1,
     -tfg => 'blue',
     -tbg => 'white',
    );
  $maintv = $maintvwin->add
    (
     'maintv',
     'TextViewer',
     -wrapping => 1,
    );
  $mainstattvwin = $mw->add
    (
     'mainstattvwin',
     'Window',
     -border => 1,
     -x => $maintvwin->x,
     -y => $maintvwin->y + $maintvwin->height,
     -height => 4,
     );
  $mainstattv = $mainstattvwin->add
    (
     'mainstattv',
     'TextViewer',
     );
  $mainlb->set_binding(\&refreshkey, &Curses::KEY_F(5));
  $mainlb->set_binding(\&refreshkey, "\cR");
  $mainlb->set_binding(sub{&change_mode('none')}, "\c[");
  $mainlb->focus;
  &update;
}

sub refreshkey {
  $saved_active_value = $mainlb->get_active_value;
  &update;
}

sub mode_exit {
  $mainstattvwin->delete('mainstattv');
  undef $mainstattv;
  $mw->delete('mainstattvwin');
  undef $mainstattvwin;
  $maintvwin->delete('maintv');
  undef $maintv;
  $mw->delete('maintvwin');
  undef $maintvwin;
  $mainlbwin->delete('mainlb');
  undef $mainlb;
  $mw->delete('mainlbwin');
  undef $mainlbwin;
  undef %services;
}

sub test_initsys() {
  # Discover what init system is in use. Currently supports only SYSV
  # and systemd.

  return if defined $initsys;
  $initsys = 'sysv';
  $initsys = 'systemd' if -e '/bin/systemctl';
}

sub update() {
  # Update the services listbox. This will be handled differently
  # based on the service init system in use.

  &test_initsys;

  # The goal is to generate a %services hash whose keys are
  # names of services ('sshd', 'httpd', etc.), and whose values are
  # hashrefs telling us things like 'descr', 'enabled', 'running',
  # etc. Now, 'enabled' and 'running' will be only true or
  # false. There might be an 'enabled_detail' or 'running_detail' that
  # tells more about why it is or isn't enabled, or is or isn't
  # running, but whether we can obtain these is dependent on the init
  # system.
  %services = ();
  if($initsys eq 'systemd') {
    my @output = `systemctl list-units -t service --all`;
    chomp @output;
    foreach my $line (@output) {
      # 'systemctl list-units' has a footer that follows after a blank
      # line; it contains a legend for humans to read, but has no
      # additional information about the services.
      last unless $line;
      # There is a Unicode bullet character that appears before some
      # lines. We have to decode the line to Perl's internal Unicode
      # format in order to be able to handle it with string functions
      # and match it with regexes.
      $line = Encode::decode('UTF-8', $line);
      # Strip leading whitespace just in case.
      $line =~ s/^\s+//;
      # This will get rid of that bullet character if it appears. We
      # don't need it for this purpose.
      $line =~ s/^\S\s+//;
      # Split the rest.
      my($unit, $load, $active, $sub, $descr) = split /\s+/, $line, 5;
      # This will skip header lines and such.
      next if !$unit or !$load or !$active or !$sub;
      next if $unit eq 'UNIT';
      # The systemd services are many and not really part of this.
      next if $unit =~ /^systemd-/;
      # Remove the .service suffix from the names of the services.
      $unit =~ s/\.service$//;
      # Build the data into the hash.
      $services{$unit} =
	{
	 descr => $descr,
	 running => ($sub eq 'running'?1:''),
	};
    }
    $cui->progress
      (
       -max => scalar(keys %services),
       -message => 'Gathering data ...',
      );
    # Now that we have the list of services, collect additional data.
    my $servicecount = 0;
    foreach my $service (keys %services) {
      my @show = `systemctl show $service.service`;
      chomp @show;
      my %data = map { split '=', $_, 2 } @show;
      $services{$service}->{enabled} = ($data{UnitFileState} and $data{UnitFileState} eq 'enabled');
      $services{$service}->{enabled_detail} = sprintf('%s/%s', ($data{UnitFileState} or '-'), ($data{LoadState} or '-'));
      $services{$service}->{running_detail} = sprintf('%s/%s', ($data{ActiveState} or '-'), ($data{SubState} or '-'));
      $servicecount++;
      $cui->setprogress($servicecount);
    }
  } elsif($initsys eq 'sysv') {
    # Likewise, but gather this data from a SYSV init system.
    my @output = `chkconfig --list`;
    chomp @output;
    foreach my $line (@output) {
      $line = Encode::decode('UTF-8', $line);
      my($service, @levels) = split /\s+/, $line;
      my($rl3on) = grep { substr($_, 0, 1) eq '3' } @levels;
      my $enabled = ($rl3on eq '3:on')?1:'';
      $services{$service} =
	{
	 enabled => $enabled,
	};
    }
    $cui->progress
      (
       -max => scalar(keys %services),
       -message => 'Gathering data ...',
      );
    my $servicecount = 0;
    foreach my $service (keys %services) {
      my $status = system("service $service status >&/dev/null") >> 8;
      $services{$service}->{running} = ($status == 0)?1:'';
      my $descr = '';
      my $fh = IO::File->new("</etc/init.d/$service");
      if($fh) {
	while(defined(my $line = <$fh>)) {
	  chomp $line;
	  if($descr eq '') {
	    next unless $line =~ /^\s*#\s*description:/i;
	    $line =~ s/^\s*#\s*description:\s*//i;
	    $descr = $line;
	  } else {
	    last unless $line =~ /^\s*#\s{2,}/;
	    $line =~ s/^\s*#\s*//;
	    $descr .= ' ' . $line;
	  }
	}
	$fh->close;
      }
      $descr =~ s/\s*\\\s*/ /g;
      $services{$service}->{descr} = $descr;
      $services{$service}->{enabled_detail} = '';
      $services{$service}->{running_detail} = '';
      $servicecount++;
      $cui->setprogress($servicecount);
    }
  }
  # Find the longest service name.
  my $service_max_width = 0;
  foreach my $service (keys %services) {
    $service_max_width = length $service if length $service > $service_max_width;
  }
  # Generate the label strings for the Curses::UI listbox lines.
  my %labels = ();
  my $label_format = sprintf "%%-%ds %%-7s %%-7s", $service_max_width;
  foreach my $service (keys %services) {
    $labels{$service} = sprintf
      ($label_format, $service,
       $services{$service}->{enabled}?'yes':'no',
       $services{$service}->{running}?'yes':'no');
  }
  my $title_format = sprintf "%%-%ds %%-7s %%-7s", $service_max_width - 1;
  $mainlbwin->title(sprintf $title_format, 'Service', 'Enabled', 'Running');
  $mainlb->values([ sort { lc($a) cmp lc($b) } keys %services ]);
  $mainlb->labels(\%labels);
  $mainlb->set_active_value($saved_active_value) if $saved_active_value;
  $mainlb->draw;
  $cui->noprogress;
}

sub service_selected($) {
  # The user has selected one of the services by one of a number of
  # means. Show the listboxes allowing the user to enable/disable the
  # service and start/stop/restart it.

  my($widget) = @_;
  my $service = $widget->get_active_value;

  # The "Enable/Disable" box
  $edlbwin->delete('edlb') if $edlb;
  $mw->delete('edlbwin') if $edlbwin;
  $edlbwin = $mw->add
    (
     'edlbwin',
     'Window',
     -border => 1,
     -x => $mainlbwin->width,
     -y => $mainstattvwin->y + $mainstattvwin->height,
     -height => 4,
     -width => 10,
     -titlefullwidth => 1,
     -tfg => 'blue',
     -tbg => 'white',
    );
  $edlb = $edlbwin->add
    (
     'edlb',
     'Listbox',
     -onselchange => sub { shift->focus; },
     -onchange => \&edlb_selected,
     -wraparound => 1,
    );
  if($services{$service}->{enabled}) {
    $edlb->values(['disable']);
    $edlb->labels({'disable' => 'Disable'});
  } else {
    $edlb->values(['enable']);
    $edlb->labels({'enable' => 'Enable'});
  }

  # The "Start/Stop/Restart" box
  $runlbwin->delete('runlb') if $runlb;
  $mw->delete('runlbwin') if $runlbwin;
  $runlbwin = $mw->add
    (
     'runlbwin',
     'Window',
     -border => 1,
     -x => $mainlbwin->width + $edlbwin->width,
     -y => $mainstattvwin->y + $mainstattvwin->height,
     -height => 4,
     -width => 10,
     -titlefullwidth => 1,
     -tfg => 'blue',
     -tbg => 'white',
    );
  $runlb = $runlbwin->add
    (
     'runlb',
     'Listbox',
     # This prevents focus from going back to $mtv, causing a
     # mostly-unresponsive state (as $mtv is in the background and
     # hidden) if this menu is selected from via mouse click when
     # unfocused:
     -onselchange => sub { shift->focus; },
     -onchange => \&runlb_selected,
     -wraparound => 1,
    );
  if($services{$service}->{running}) {
    $runlb->values(['restart', 'stop']);
    $runlb->labels({'restart' => 'Restart', 'stop' => 'Stop'});
  } else {
    $runlb->values(['restart', 'start']);
    $runlb->labels({'restart' => 'Restart', 'start' => 'Start'});
  }
  $edlb->set_binding(\&close_boxes, "\c[");
  $edlb->set_binding(\&close_boxes, &Curses::KEY_LEFT);
  $edlb->set_binding(sub{$runlb->focus}, &Curses::KEY_RIGHT);
  $edlb->set_binding(sub{$runlb->focus}, "\t");
  $edlb->set_binding(sub{$runlb->focus}, &Curses::KEY_BTAB);
  $runlb->set_binding(\&close_boxes, "\c[");
  $runlb->set_binding(sub{$edlb->focus}, &Curses::KEY_LEFT);
  $runlb->set_binding(sub{}, &Curses::KEY_RIGHT);
  $runlb->set_binding(sub{$edlb->focus}, "\t");
  $runlb->set_binding(sub{$edlb->focus}, &Curses::KEY_BTAB);
  $edlb->focus;
  $edlbwin->draw;
  $runlbwin->draw;
}

sub highlight_changed($) {
  # This is called when the user changes the highlighted line in the
  # listbox using the arrow keys, PgUp, PgDown, clicking with the
  # mouse, etc. Basically we're going to change the contents of the
  # info boxes to give more info about the service that is
  # highlighted. The argument given is the widget that the onselchange
  # event is set on, meaning the listbox object.

  my($widget) = @_;
  my $service = $widget->get_active_value;
  $maintvwin->title("Service $service:");
  my $enabled = $services{$service}->{enabled}?'yes':'no';
  my $running = $services{$service}->{running}?'yes':'no';
  $maintv->text(<<"EOT");
Description: $services{$service}->{descr}
EOT
  ;
#  $maintvwin->draw;
  $mainstattv->text(<<"EOT");
Enabled: $enabled ($services{$service}->{enabled_detail})
Running: $running ($services{$service}->{running_detail})
EOT
  ;
#  $mainstattvwin->draw;
  $mw->draw;
}

sub edlb_selected($) {
  # The user has selected something in the "Enable"/"Disable" listbox.

  my($widget) = @_;

  $saved_active_value = $mainlb->get_active_value;
  my $action = $widget->get_active_value;
  if($action eq 'enable') {
    if($initsys eq 'systemd') {
      system("systemctl enable $saved_active_value.service >&/dev/null");
    } elsif($initsys eq 'sysv') {
      system("chkconfig $saved_active_value on >&/dev/null");
    }
  } elsif($action eq 'disable') {
    if($initsys eq 'systemd') {
      system("systemctl disable $saved_active_value.service >&/dev/null");
    } elsif($initsys eq 'sysv') {
      system("chkconfig $saved_active_value off >&/dev/null");
    }
  }
  &close_boxes;
  &update;
}

sub runlb_selected($) {
  # The user has selected something in the "run" listbox, like
  # "start", "stop", or "restart".

  my($widget) = @_;

  $saved_active_value = $mainlb->get_active_value;
  my $action = $widget->get_active_value;
  if($action eq 'restart') {
    if($initsys eq 'systemd') {
      system("systemctl restart $saved_active_value.service >&/dev/null");
    } elsif($initsys eq 'sysv') {
      system("service $saved_active_value restart >&/dev/null");
    }
  } elsif($action eq 'start') {
    if($initsys eq 'systemd') {
      system("systemctl start $saved_active_value.service >&/dev/null");
    } elsif($initsys eq 'sysv') {
      system("service $saved_active_value start >&/dev/null");
    }
  } elsif($action eq 'stop') {
    if($initsys eq 'systemd') {
      system("systemctl stop $saved_active_value.service >&/dev/null");
    } elsif($initsys eq 'sysv') {
      system("service $saved_active_value stop >&/dev/null");
    }
  }
  &close_boxes;
  &update;
}

sub close_boxes {
  # Backing out of the action boxes by various means should cause
  # those boxes to disappear and focus to return to the main listbox.

  $edlbwin->delete('edlb');
  undef $edlb;
  $mw->delete('edlbwin');
  undef $edlbwin;
  $runlbwin->delete('runlb');
  undef $runlb;
  $mw->delete('runlbwin');
  undef $runlbwin;
  $mainlb->focus;
  $mainlb->clear_selection;
  $mainlbwin->draw;
}

1;
