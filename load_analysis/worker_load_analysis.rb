#/usr/bin/env ruby

CLOUD_ID = 1
# START_TIME = Time.gm(2011,07,20,0,0,0)
DURATION = 24.hours
START_TIME = Time.now - DURATION
EXCLUDE_LOW_PRIORITY = true
# DATA_POINTS = 6.hours / 15.seconds
DATA_POINTS = 1440

#####################################################################

@start_time = START_TIME
@end_time = START_TIME + DURATION
@worker_types = {}
@cloud = Cloud.find(CLOUD_ID)
@cloud.worker_types.all.each { |wt| @worker_types[wt.id] = wt }

@workers = @cloud.workers.find(:all, :select => 'id,worker_type_id,state,created_at,alive_at,killed_at,updated_at,url,instance_id', :conditions => ["(killed_at >= ? OR (killed_at is null AND updated_at >= ?)) AND created_at < ?", @start_time, @start_time, @end_time])
@inputs = @cloud.input_media_files.find(:all, :select => 'id,account_id,state,created_at,started_at,finished_at,times,low_priority', :conditions => ["(finished_at is null or finished_at >= ?) and created_at < ? and state != 'cancelled'", @start_time, @end_time])
@outputs = @cloud.output_media_files.find(:all, :select => 'id,account_id,job_id,state,created_at,started_at,finished_at,times,low_priority,cached_queue_time,cached_total_time,estimated_transcode_load', :conditions => ["(finished_at is null or finished_at >= ?) and created_at < ? and state != 'cancelled'", @start_time, @end_time])


@worker_time_data = []
@workers.each do |worker|
  next unless worker.instance_id.present? # Filter out bad calls to amazon.

  # For now we ignore all debugging/stopped/etc workers.
  next unless worker.killed_at || ['launching','active','terminating','updating','disappeared'].include?(worker.state)

  if worker.url.blank? && ['terminated','disappeared'].include?(worker.state)
    @worker_time_data << { :type => :bad_launch, :time => worker.created_at.to_i }
    @worker_time_data << { :type => :bad_kill, :time => worker.updated_at.to_i }
  elsif worker.url.present? || ['launching'].include?(worker.state)
    # Good worker.
    @worker_time_data << { :type => :launched, :time => worker.created_at.to_i }
    @worker_time_data << { :type => :active, :time => (worker.alive_at || Time.now + 1.year).to_i }
    @worker_time_data << { :type => :killed, :time => (worker.killed_at || Time.now + 1.year).to_i }
  else
    puts "Ignoring bad worker record - #{worker.id}"
  end

end
@worker_time_data = @worker_time_data.sort_by { |d| d[:time] }

# @input_total_times = {}
@input_time_data = []
@inputs.each do |input|
  next unless input.finished_at || ['waiting','processing'].include?(input.state)
  next if EXCLUDE_LOW_PRIORITY && input.low_priority

  @input_time_data << { :type => :queued, :time => input.created_at.to_i }
  @input_time_data << { :type => :started, :time => (input.started_at || Time.now + 1.year).to_i}
  @input_time_data << { :type => :finished, :time => (input.finished_at || Time.now + 1.year).to_i}
  
  # @input_total_times[input.id] = input.total_time rescue nil
end
@input_time_data = @input_time_data.sort_by { |d| d[:time] }

@output_time_data = []
@outputs.each do |output|
  next if output.state == 'no_input'
  next unless output.finished_at || ['ready','processing'].include?(output.state)
  next if EXCLUDE_LOW_PRIORITY && output.low_priority

  # We'll figure out still-processing or still-ready files later...
  next unless output.finished_at
  
  # Will figure this out later too.
  next if output.state == 'failed'
  
  if !output.cached_queue_time
    puts "Don't know what to do with output #{output.id}!"
    next
  end

  processing_start = output.finished_at - (output.transcode_time.to_f + output.upload_time.to_f)
  queue_start = processing_start - output.cached_queue_time.to_f
  load = output.estimated_transcode_load || 200

  @output_time_data << { :type => :queued, :time => queue_start.to_i, :load => load }
  @output_time_data << { :type => :started, :time => processing_start.to_i, :load => load }
  @output_time_data << { :type => :finished, :time => output.finished_at.to_i, :load => load }
end
@output_time_data = @output_time_data.sort_by { |d| d[:time] }

puts "Stats Collected: #{@worker_time_data.length} worker entries, #{@input_time_data.length} input entries, #{@output_time_data.length} output entries"


#################################################################################

f = File.open('worker_count_chart.html', 'w')
f.puts <<END_HTML
<html>
  <head>
    <script type="text/javascript" src="https://www.google.com/jsapi"></script>
    <script type="text/javascript">
      google.load("visualization", "1", {packages:["corechart"]});
    </script>
  </head>
  <body>
END_HTML

  f.puts "<div id=\"chart_div\"></div>"
  f.puts "<script type=\"text/javascript\">"
  f.puts "var data = new google.visualization.DataTable();"
  f.puts "data.addColumn('string','Time')"

  f.puts "data.addColumn('number','Launched Workers')"
  f.puts "data.addColumn('number','Active Workers')"
  f.puts "data.addColumn('number','Bad Workers')"
  # f.puts "data.addColumn('number','Queued Inputs')"
  f.puts "data.addColumn('number','Processing Inputs')"
  # f.puts "data.addColumn('number','Queued Outputs')"
  # f.puts "data.addColumn('number','Queued Output Load')"
  f.puts "data.addColumn('number','Processing Outputs')"
  f.puts "data.addColumn('number','Processing Output Load')"

  f.puts "data.addRows(["

  @data_points = {
    :launched_workers => [0],
    :active_workers => [0],
    :bad_workers => [0],
    :queued_inputs => [0],
    :processing_inputs => [0],
    :queued_outputs => [0],
    :queued_output_load => [0],
    :processing_outputs => [0],
    :processing_output_load => [0],
  }
  @baselines = {
    :launched_workers => 0,
    :active_workers => 0,
    :bad_workers => 0,
    :queued_inputs => 0,
    :processing_inputs => 0,
    :queued_outputs => 0,
    :queued_output_load => 0,
    :processing_outputs => 0,
    :processing_output_load => 0,
  }
  
  @granularity = (@end_time - @start_time) / DATA_POINTS.to_f

  ############# SET UP WORKER DATA ##############
  prev_point = 0
  @worker_time_data.each do |data|
    data_type = data[:type]

    # For events before the graph, just update the baselines.
    if data[:time] < @start_time.to_i
      case data_type
      when :launched
        @baselines[:launched_workers] += 1
      when :active
        @baselines[:active_workers] += 1
      when :bad_launch
        @baselines[:bad_workers] += 1
      when :bad_kill
        # Sometimes the sql query will include old bad workers.  Account for them.
        @baselines[:bad_workers] -= 1
      end

      next
    end

    offset = data[:time] - @start_time.to_i
    point_loc = (offset / @granularity).round
    
    while prev_point < point_loc
      [:launched_workers, :active_workers, :bad_workers].each do |data_set|
        @data_points[data_set][prev_point + 1] = @data_points[data_set][prev_point]
      end
      prev_point += 1
    end
    
    case data_type
    when :launched
      @data_points[:launched_workers][point_loc] += 1
    when :active
      @data_points[:active_workers][point_loc] += 1
    when :killed
      @data_points[:launched_workers][point_loc] -= 1
      @data_points[:active_workers][point_loc] -= 1
    when :bad_launch
      @data_points[:bad_workers][point_loc] += 1
    when :bad_kill
      @data_points[:bad_workers][point_loc] -= 1
    end
  end

  ############# SET UP INPUTS DATA ##############
  prev_point = 0
  @input_time_data.each do |data|
    data_type = data[:type]

    # For events before the graph, just update the baselines.
    if data[:time] < @start_time.to_i
      case data_type
      when :queued
        @baselines[:queued_inputs] += 1
      when :started
        @baselines[:processing_inputs] += 1
      end

      next
    end

    offset = data[:time] - @start_time.to_i
    point_loc = (offset / @granularity).round
    
    while prev_point < point_loc
      [:queued_inputs, :processing_inputs].each do |data_set|
        @data_points[data_set][prev_point + 1] = @data_points[data_set][prev_point]
      end
      prev_point += 1
    end
    
    case data_type
    when :queued
      @data_points[:queued_inputs][point_loc] += 1
    when :started
      @data_points[:processing_inputs][point_loc] += 1
    when :finished
      @data_points[:queued_inputs][point_loc] -= 1
      @data_points[:processing_inputs][point_loc] -= 1
    end
  end

  ############# SET UP OUPUTS DATA ##############
  prev_point = 0
  @output_time_data.each do |data|
    data_type = data[:type]

    # For events before the graph, just update the baselines.
    if data[:time] < @start_time.to_i
      case data_type
      when :queued
        @baselines[:queued_outputs] += 1
        @baselines[:queued_output_load] += data[:load]
      when :started
        @baselines[:processing_outputs] += 1
        @baselines[:processing_output_load] += data[:load]
      end

      next
    end

    offset = data[:time] - @start_time.to_i
    point_loc = (offset / @granularity).round
    
    while prev_point < point_loc
      [:queued_outputs, :processing_outputs, :queued_output_load, :processing_output_load].each do |data_set|
        @data_points[data_set][prev_point + 1] = @data_points[data_set][prev_point]
      end
      prev_point += 1
    end
    
    case data_type
    when :queued
      @data_points[:queued_outputs][point_loc] += 1
      @data_points[:queued_output_load][point_loc] += data[:load]
    when :started
      @data_points[:processing_outputs][point_loc] += 1
      @data_points[:processing_output_load][point_loc] += data[:load]
    when :finished
      @data_points[:queued_outputs][point_loc] -= 1
      @data_points[:queued_output_load][point_loc] -= data[:load]
      @data_points[:processing_outputs][point_loc] -= 1
      @data_points[:processing_output_load][point_loc] -= data[:load]
    end
  end

  ############# SCALE DOWN OUTPUT LOAD ###########
  max_outputs = @data_points[:queued_outputs].max
  max_load = @data_points[:queued_output_load].max
  scale = max_outputs.to_f / max_load
  @baselines[:queued_output_load] = (@baselines[:queued_output_load] * scale).round
  @data_points[:queued_output_load].each_with_index do |value,index|
    @data_points[:queued_output_load][index] = (value * scale).round
  end
  

  max_outputs = @data_points[:processing_outputs].max
  max_load = @data_points[:processing_output_load].max
  scale = max_outputs.to_f / max_load
  @baselines[:processing_output_load] = (@baselines[:processing_output_load] * scale).round
  @data_points[:processing_output_load].each_with_index do |value,index|
    @data_points[:processing_output_load][index] = (value * scale).round
  end

  zone = -5.hours
  DATA_POINTS.times do |p|
    time = (@start_time + (p*@granularity) + zone).strftime('%H:%M')
    values = []
    # [:launched_workers, :active_workers, :bad_workers, :queued_inputs, :processing_inputs, :queued_outputs, :queued_output_load, :processing_outputs, :processing_output_load].each do |data_set|
    [:launched_workers, :active_workers, :bad_workers, :processing_inputs, :processing_outputs, :processing_output_load].each do |data_set|
      values << @baselines[data_set] + @data_points[data_set][p].to_i
    end
    f.puts "  ['%s', %s]," % [time, values.join(',')]
  end
  
  f.puts "]);"
  f.puts "var chart = new google.visualization.AreaChart(document.getElementById('chart_div'));"

  invert_colors = true
  inverted_color_spec = ", backgroundColor: 'black', gridlineColor: '#444', legendTextStyle: { color: '#ccc' }, hAxis: { baselineColor: '#999', textStyle: { color: '#ccc' }, titleTextStyle: { color: '#ccc' } }, vAxis: { baselineColor: '#999', titleTextStyle: { color: '#ccc' }, textStyle: { color: '#ccc' } }"

  f.puts "chart.draw(data, { isStacked: false, lineWidth: 1, width: 1440, height: 800 #{inverted_color_spec if invert_colors} });"
  f.puts "</script>"

f.puts <<END_HTML
  </body>
</html>
END_HTML

f.close
