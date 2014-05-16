# Check for files that are stuck assigning, for whatever reason, and revert them back so they can be assigned again.
# Note that we have a separate stuck-assigning monitor that should be set to at least a minute longer than this one.

def cur_time_string
  "[#{Time.now.utc.to_s(:logging)}]"
end

def redis_queues_in_normal_range(host)
  queue = Zencoder::Redis::Queue.connect(host)
  queue.length("worker_comm_input") < 300 && queue.length("worker_comm_output") < 300
end

def log(message)
  puts "#{cur_time_string} #{message}"
end

log "Begin script run"

locked = Locker.run("fix_stuck_jobs") do
  # Proceed only if the number of queued items in Redis is in the normal
  # range.  A high number could indicate slow/disrupted network connectivity,
  # which is not grounds for reassigning items.  In fact, reassinging items
  # could lead to duplicate assignment and a thundering-herd situation once
  # connectivity is restored (4/30/2014 EC2 incident).
  #
  # Will check the Redis queue length on utility1 and utility2(localhost)
  if redis_queues_in_normal_range("utility1.fal.zencoderdns.net:6379/1") &&
     redis_queues_in_normal_range("127.0.0.1:6379/1")

    assignment_retry_timeout = Zencoder::Config.get(:assignment_retry_timeout, 2).minutes

    stuck_inputs = InputMediaFile.with_state(:assigning).find(:all, :select => 'id', :conditions => ["updated_at < ?", assignment_retry_timeout.ago])

    stuck_inputs.each do |input|
      log "Fixing input #{input.id}"
      # Only change it back to waiting if it's still assigning.
      InputMediaFile.update_all({ :worker_id => nil, :state => 'waiting' }, { :id => input.id, :state => 'assigning' })
    end

    stuck_outputs = OutputMediaFile.with_state(:assigning).find(:all, :select => 'id', :conditions => ["updated_at < ?", assignment_retry_timeout.ago])

    stuck_outputs.each do |output|
      log "Fixing output #{output.id}"
      # Only change it back to ready if it's still assigning.
      OutputMediaFile.update_all({ :worker_id => nil, :state => 'ready' }, { :id => output.id, :state => 'assigning' })
    end

    log "No stuck files to fix" if stuck_inputs.empty? && stuck_outputs.empty?
  else
    log "Aborting, Redis queues have a large backlog which could be an indication of network connectivity issues."
  end
end

log "Unable to obtain lock, another script must be running" unless locked

log "End script run"
