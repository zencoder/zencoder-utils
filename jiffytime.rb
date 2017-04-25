#!/usr/bin/env ruby

require 'etc'

# Get the system's Jiffy Hz value -- the unit that all the clock values will be in.
def get_hz_value
  return @hz_value if @hz_value
  hz = Etc.sysconf(Etc::SC_CLK_TCK).to_i
  hz = 100 if hz == 0
  @hz_value = hz
end


def getstats(pid)
  # pid           process id
  # tcomm         filename of the executable
  # state         state (R is running, S is sleeping, D is sleeping in an
  #               uninterruptible wait, Z is zombie, T is traced or stopped)
  # ppid          process id of the parent process
  # pgrp          pgrp of the process
  # sid           session id
  # tty_nr        tty the process uses
  # tty_pgrp      pgrp of the tty
  # flags         task flags
  # min_flt       number of minor faults
  # cmin_flt      number of minor faults with child's
  # maj_flt       number of major faults
  # cmaj_flt      number of major faults with child's
  # utime         user mode jiffies
  # stime         kernel mode jiffies
  # cutime        user mode jiffies with child's      # NOTE: Through manual testing, I've confirmed this is ONLY child jiffies, not including parent.
  # cstime        kernel mode jiffies with child's    # NOTE: Through manual testing, I've confirmed this is ONLY child jiffies, not including parent.

  # Note: Wait 'til state is Z to collect jiffies, because as soon as we call Process.wait on the pid, the proc stats go away.

  data = File.read("/proc/#{pid.to_i}/stat").split(/\s+/) rescue []
  # puts data.inspect

  stats = {
    :state => data[2],
    :utime => data[13].to_i,
    :stime => data[14].to_i,
    :cutime => data[15].to_i,
    :cstime => data[16].to_i,
    :total_user => data[13].to_i + data[15].to_i,
    :total_system => data[14].to_i + data[16].to_i,
    :total_time => data[13].to_i + data[15].to_i + data[14].to_i + data[16].to_i
  }
  # puts stats.inspect

  stats
end

def handle_sigchld
  return if @child_exited # In case we get another sigchild after the main process finishes - so we don't trigger the error message.

  stats = getstats(@child_pid)
  if stats[:state] == 'Z'
    @child_stats = stats
    @child_exited = true
  elsif stats[:state].nil?
    puts "JIFFY TRACKING FAILED!"
    @child_exited = true
  end
end
Signal.trap("CHLD") { handle_sigchld }


# puts "ARGV: #{ARGV.inspect}"

@child_stats = nil
@child_exited = false
@before_time = Time.now

@child_pid = Process.spawn(*ARGV)
# puts "CHILD PID: #{@child_pid}"
sleep 0.01 until @child_exited
@after_time = Time.now

Process.waitpid(@child_pid) rescue nil
@elapsed_time = @after_time - @before_time

puts
if @child_stats
  # puts "CHILD STATS: #{@child_stats.inspect}"
  puts "User Time:   %6.2f seconds / %6d jiffies" % [@child_stats[:total_user].to_f / get_hz_value, @child_stats[:total_user]]
  puts "System Time: %6.2f seconds / %6d jiffies" % [@child_stats[:total_system].to_f / get_hz_value, @child_stats[:total_system]]
  puts "CPU Time:    %6.2f seconds / %6d jiffies" % [@child_stats[:total_time].to_f / get_hz_value, @child_stats[:total_time]]
end

puts   "Real Time:   %6.2f seconds" % [@elapsed_time]
puts