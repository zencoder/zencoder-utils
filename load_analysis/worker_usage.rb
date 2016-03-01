# For now only do this for a few main clouds - us-east, eu-dublin, and us-oregon

Worker.logger.level = 10
OutputMediaFile.logger.level = 10

cloud_list = [1,3,6]
first_day = '2016-02-01'
last_day = '2016-02-29'

puts ['DATE', 'CLOUD_ID', 'WORKER_ID', 'INSTANCE_TYPE', 'LIFECYCLE', 'LAUNCHED', 'KILLED', 'TARGET_LOAD', 'MAX_LOAD', 'TARGET_LOAD_SECONDS', 'MAX_LOAD_SECONDS', 'OUTPUT_COUNT', 'USED_LOAD_SECONDS'].join("\t")

cloud_list.each do |cloud_id|
  run_report(cloud_id, first_day, last_day)
end; nil



#############################################################


def log(message)
  now = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
  STDERR.puts "STATUS: #{now} #{message}"
end

def run_report(cloud_id, first_day_string, last_day_string)
  first_day = DateTime.parse(first_day_string)
  last_day  = DateTime.parse(last_day_string)

  current_day = first_day
  while current_day <= last_day
    generate_daily_stats(cloud_id, current_day)

    current_day += 24.hours
  end
end


def generate_daily_stats(cloud_id, day)
  log "Generating report for cloud #{cloud_id}, #{day} ..."

  next_day = day + 24.hours

  log "  Loading workers..."
  workers = {}
  Worker.where(cloud_id: cloud_id).where("(killed_at is NULL AND state = 'active') OR killed_at >= ?", day).where("launched_at < ?", next_day).all.each do |w|
    workers[w.id] = { 
      worker: w,
      launched: w.launched_at,
      killed: w.killed_at,
      target_load: w.machine_type.target_load,
      max_load: w.available_machine_type.max_load,
      instance_type: w.machine_type.instance_type,
      lifecycle: w.spot? ? 'SPOT' : 'ON-DEMAND',
      events: Hash.new { |h,k| h[k] = 0 }
    }
  end; nil

  log "  Loaded #{workers.size} workers..."

  total_output_count = 0
  worker_count = 0
  workers.each_pair do |wid, worker|
    worker_start = [day.to_i, worker[:launched].to_i].max
    worker_finish = [next_day.to_i, (worker[:killed] || next_day).to_i].min

    count = 0
    OutputMediaFile.where(worker_id: wid).select('id,estimated_transcode_load,started_at,finished_at').each do |output|
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

      count += 1
    end; nil

    total_output_count += count

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


    # puts ['DATE', 'CLOUD_ID', 'WORKER_ID', 'INSTANCE_TYPE', 'LIFECYCLE', 'LAUNCHED', 'KILLED', 'TARGET_LOAD', 'MAX_LOAD', 'TARGET_LOAD_SECONDS', 'MAX_LOAD_SECONDS', 'OUTPUT_COUNT', 'USED_LOAD_SECONDS'].join("\t")

    clean_date = day.strftime('%Y-%m-%d')
    puts [clean_date, cloud_id, wid, worker[:instance_type], worker[:lifecycle], worker[:launched], worker[:killed], worker[:target_load], worker[:max_load], total_target_capacity, total_max_capacity, count, used_capacity].join("\t")

    worker_count += 1
    if (worker_count % 100) == 0
      log "    Processed #{worker_count} workers..."
    end
  end

  log "  Total outputs for day: #{total_output_count}"
end

