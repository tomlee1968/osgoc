#!/usr/bin/env ruby

hostname = `hostname`.strip
umask_line = `grep -E '^[[:space:]]*umask[[:space:]]+[0-7]+[[:space:]]*$' /etc/profile.d/custom.sh`
umask = (umask_line.split)[1]
if umask != '022'
  IO.popen("mail -s 'Unusual umask on #{hostname}: #{umask}' thomlee@iu.edu", 'w') do |p|
    p.puts "Unusual umask on #{hostname}: #{umask}"
  end
end
