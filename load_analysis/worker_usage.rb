
@cloud_id = 1
@day_start = DateTime.parse('2016-02-23 00:00:00')
@day_end   = @day_start + 24.hours

puts "Loading workers..."

@workers = {}
Worker.where(cloud_id: @cloud_id).where("(killed_at is NULL AND state = 'active') OR killed_at > ?", @day_start).where("launched_at <= ?", @day_end).all.each do |w|
  @workers[w.id] = { 
    worker: w,
    launched: w.launched_at,
    killed: w.killed_at,
    target_load: w.machine_type.target_load,
    max_load: w.available_machine_type.max_load,
    events: Hash.new { |h,k| h[k] = 0 }
  }
end; nil

puts "Loaded #{@workers.size} workers..."

puts
puts ['ID', 'LAUNCHED', 'KILLED', 'TARGET_LOAD', 'MAX_LOAD', 'TARGET_LOAD_SECONDS', 'MAX_LOAD_SECONDS', 'USED_LOAD_SECONDS'].join("\t")

@workers.each_pair do |wid, worker|
  worker_start = [@day_start.to_i, worker[:launched].to_i].max
  worker_finish = [@day_end.to_i, (worker[:killed] || @day_end).to_i].min

  count = 0
  OutputMediaFile.where(worker_id: wid).select('id,estimated_transcode_load,started_at,finished_at').each do |output|
    # break if count > 0
    count += 1
    # puts output.inspect
    next unless (output.estimated_transcode_load && output.started_at && output.finished_at)
    # puts "Output #{output.id}"
    load = output.estimated_transcode_load.to_i
    start_seconds = output.started_at.to_i
    finish_seconds = output.finished_at.to_i
    # puts "  Start: #{start_seconds}"
    # puts "  Finish: #{finish_seconds}"
    next if finish_seconds < worker_start
    next if start_seconds > worker_finish
    # puts "   Load: #{load}"
    worker[:events][start_seconds] += load
    worker[:events][finish_seconds] -= load
  end; nil

  total_max_capacity = (worker_finish - worker_start) * worker[:max_load]
  total_target_capacity = (worker_finish - worker_start) * worker[:target_load]

  previous_event_time = worker_start
  current_load = 0
  used_capacity = 0
  worker[:events].keys.sort.each do |event_time|
    value = worker[:events][event_time]
    if event_time <= worker_start
      current_load += value
    elsif event_time >= worker_finish
      duration = worker_finish - previous_event_time
      used_capacity += (duration * current_load)
      break
    else
      duration = event_time - previous_event_time
      used_capacity += (duration * current_load)
      previous_event_time = event_time
      current_load += value
    end
  end
  
  # puts "Worker #{wid}: target=#{worker[:target_load]}, max=#{worker[:max_load]}, launched=#{worker[:launched]}, killed=#{worker[:killed]}"
  # puts "  total_max_capacity:    #{total_max_capacity}, used_capacity: #{used_capacity}, percent: #{100.0 * used_capacity / total_max_capacity}"
  # puts "  total_target_capacity: #{total_target_capacity}, used_capacity: #{used_capacity}, percent: #{100.0 * used_capacity / total_target_capacity}"

  puts [wid, worker[:launched], worker[:killed], worker[:target_load], worker[:max_load], total_target_capacity, total_max_capacity, used_capacity].join("\t")
end; nil


