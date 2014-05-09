# Check for files that are stuck assigning, for whatever reason, and revert them back so they can be assigned again.
# Note that we have a separate stuck-assigning monitor that should be set to at least a minute longer than this one.

def cur_time_string
  "[#{Time.now.utc.strftime('%F %T %z')}]"
end

puts "#{cur_time_string} Begin script run"

assignment_retry_timeout = Zencoder::Config.get(:assignment_retry_timeout, 2).minutes

stuck_inputs = InputMediaFile.with_state(:assigning).find(:all, :select => 'id', :conditions => ["updated_at < ?", assignment_retry_timeout.ago])

stuck_inputs.each do |input|
  puts "#{cur_time_string} Fixing input #{input.id}"
  # Only change it back to waiting if it's still assigning.
  InputMediaFile.update_all({ :worker_id => nil, :state => 'waiting' }, { :id => input.id, :state => 'assigning' })
end

stuck_outputs = OutputMediaFile.with_state(:assigning).find(:all, :select => 'id', :conditions => ["updated_at < ?", assignment_retry_timeout.ago])

stuck_outputs.each do |output|
  puts "#{cur_time_string} Fixing output #{output.id}"
  # Only change it back to ready if it's still assigning.
  OutputMediaFile.update_all({ :worker_id => nil, :state => 'ready' }, { :id => output.id, :state => 'assigning' })
end

puts "#{cur_time_string} End script run"

