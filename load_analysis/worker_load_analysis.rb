#/usr/bin/env ruby

TIME_OFFSET = -5.hours
CLOUD_ID = 1
EXCLUDE_LOW_PRIORITY = true

DURATION = 6.hours
START_TIME = Time.now - DURATION
# START_TIME = Time.gm(2011,07,20,0,0,0)
DATA_POINTS = 1440
# DATA_POINTS = 6.hours / 15.seconds

SETS_TO_SHOW = [:launched_workers, :active_workers, :bad_workers, :launched_worker_input_capacity, :active_worker_input_capacity, :bad_worker_input_capacity, :launched_worker_output_capacity, :active_worker_output_capacity, :bad_worker_output_capacity, :queued_inputs, :processing_inputs, :queued_outputs, :queued_output_load, :processing_outputs, :processing_output_load]
# SETS_TO_SHOW = [:launched_workers, :active_workers, :queued_inputs, :processing_inputs, :queued_output_load, :processing_output_load, :active_worker_output_capacity]

#####################################################################

@sets_config = {
  :launched_workers                => { :color => '#333399', :desc => 'Launched Workers' },
  :active_workers                  => { :color => '#9999ff', :desc => 'Active Workers' },
  :bad_workers                     => { :color => '#663399', :desc => 'Bad Workers' },
  :launched_worker_input_capacity  => { :color => '#339933', :desc => 'Launched Worker Input Capacity' },
  :active_worker_input_capacity    => { :color => '#99ff66', :desc => 'Active Worker Input Capacity' },
  :bad_worker_input_capacity       => { :color => '#669900', :desc => 'Bad Worker Input Capacity' },
  :launched_worker_output_capacity => { :color => '#339999', :desc => 'Launched Worker Output Capacity' },
  :active_worker_output_capacity   => { :color => '#99ffff', :desc => 'Active Worker Output Capacity' },
  :bad_worker_output_capacity      => { :color => '#66ffff', :desc => 'Bad Worker Output Capacity' },
  :queued_inputs                   => { :color => '#993333', :desc => 'Queued Inputs' },
  :processing_inputs               => { :color => '#ff6699', :desc => 'Processing Inputs' },
  :queued_outputs                  => { :color => '#339966', :desc => 'Queued Outputs' },
  :queued_output_load              => { :color => '#669966', :desc => 'Queued Output Load' },
  :processing_outputs              => { :color => '#99ffcc', :desc => 'Processing Outputs' },
  :processing_output_load          => { :color => '#ccffcc', :desc => 'Processing Output Load' },
}


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

  input_capacity = @worker_types[worker.worker_type_id].max_downloads || 6
  output_capacity = @worker_types[worker.worker_type_id].max_load || 900

  if worker.url.blank? && ['terminated','disappeared'].include?(worker.state)
    @worker_time_data << { :type => :bad_launch, :time => worker.created_at.to_i, :input_capacity => input_capacity, :output_capacity => output_capacity }
    @worker_time_data << { :type => :bad_kill, :time => worker.updated_at.to_i, :input_capacity => input_capacity, :output_capacity => output_capacity }
  elsif worker.url.present? || ['launching'].include?(worker.state)
    # Good worker.
    @worker_time_data << { :type => :launched, :time => worker.created_at.to_i, :input_capacity => input_capacity, :output_capacity => output_capacity }
    @worker_time_data << { :type => :active, :time => (worker.alive_at || Time.now + 1.year).to_i, :input_capacity => input_capacity, :output_capacity => output_capacity }
    @worker_time_data << { :type => :killed, :time => (worker.killed_at || Time.now + 1.year).to_i, :input_capacity => input_capacity, :output_capacity => output_capacity }
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

  SETS_TO_SHOW.each do |data_set|
    f.puts "data.addColumn('number','#{@sets_config[data_set][:desc]}')"
  end

  f.puts "data.addRows(["


  # Initialize all set data points to an array with an intitial zero.
  @data_points = { }
  @sets_config.keys.each { |k| @data_points[k] = [0] }

  # Initialize all baselines to zero.
  @baselines = { }
  @sets_config.keys.each { |k| @baselines[k] = 0 }
  
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
        @baselines[:launched_worker_input_capacity] += data[:input_capacity]
        @baselines[:launched_worker_output_capacity] += data[:output_capacity]
      when :active
        @baselines[:active_workers] += 1
        @baselines[:active_worker_input_capacity] += data[:input_capacity]
        @baselines[:active_worker_output_capacity] += data[:output_capacity]
      when :bad_launch
        @baselines[:bad_workers] += 1
        @baselines[:bad_worker_input_capacity] += data[:input_capacity]
        @baselines[:bad_worker_output_capacity] += data[:output_capacity]
      when :bad_kill
        # Sometimes the sql query will include old bad workers.  Account for them.
        @baselines[:bad_workers] -= 1
        @baselines[:bad_worker_input_capacity] -= data[:input_capacity]
        @baselines[:bad_worker_output_capacity] -= data[:output_capacity]
      end

      next
    end

    offset = data[:time] - @start_time.to_i
    point_loc = (offset / @granularity).round
    
    while prev_point < point_loc
      [:launched_workers, :launched_worker_input_capacity, :launched_worker_output_capacity,
       :active_workers, :active_worker_input_capacity, :active_worker_output_capacity,
       :bad_workers, :bad_worker_input_capacity, :bad_worker_output_capacity].each do |data_set|
        @data_points[data_set][prev_point + 1] = @data_points[data_set][prev_point]
      end
      prev_point += 1
    end
    
    case data_type
    when :launched
      @data_points[:launched_workers][point_loc] += 1
      @data_points[:launched_worker_input_capacity][point_loc] += data[:input_capacity]
      @data_points[:launched_worker_output_capacity][point_loc] += data[:output_capacity]
    when :active
      @data_points[:active_workers][point_loc] += 1
      @data_points[:active_worker_input_capacity][point_loc] += data[:input_capacity]
      @data_points[:active_worker_output_capacity][point_loc] += data[:output_capacity]
    when :killed
      @data_points[:launched_workers][point_loc] -= 1
      @data_points[:launched_worker_input_capacity][point_loc] -= data[:input_capacity]
      @data_points[:launched_worker_output_capacity][point_loc] -= data[:output_capacity]
      @data_points[:active_workers][point_loc] -= 1
      @data_points[:active_worker_input_capacity][point_loc] -= data[:input_capacity]
      @data_points[:active_worker_output_capacity][point_loc] -= data[:output_capacity]
    when :bad_launch
      @data_points[:bad_workers][point_loc] += 1
      @data_points[:bad_worker_input_capacity][point_loc] += data[:input_capacity]
      @data_points[:bad_worker_output_capacity][point_loc] += data[:output_capacity]
    when :bad_kill
      @data_points[:bad_workers][point_loc] -= 1
      @data_points[:bad_worker_input_capacity][point_loc] -= data[:input_capacity]
      @data_points[:bad_worker_output_capacity][point_loc] -= data[:output_capacity]
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
  max_outputs = [
    @data_points[:queued_outputs].max + @baselines[:queued_outputs],
    @data_points[:processing_outputs].max + @baselines[:processing_outputs],
  ].max
  max_capacity = [
    @data_points[:launched_worker_output_capacity].max + @baselines[:launched_worker_output_capacity],
    @data_points[:active_worker_output_capacity].max + @baselines[:active_worker_output_capacity],
    @data_points[:bad_worker_output_capacity].max + @baselines[:bad_worker_output_capacity],
  ].max
  scale = max_outputs.to_f / max_capacity
  
  [:queued_output_load, :launched_worker_output_capacity, :processing_output_load, :active_worker_output_capacity, :bad_worker_output_capacity].each do |data_set|
    @baselines[data_set] = (@baselines[data_set] * scale).round
    @data_points[data_set].each_with_index do |value,index|
      @data_points[data_set][index] = (value * scale).round
    end
  end

  DATA_POINTS.times do |p|
    time = (@start_time + (p*@granularity) + TIME_OFFSET).strftime('%H:%M')
    values = []
    SETS_TO_SHOW.each do |data_set|
      values << @baselines[data_set] + @data_points[data_set][p].to_i
    end
    f.puts "  ['%s', %s]," % [time, values.join(',')]
  end
  
  f.puts "]);"
  f.puts "var chart = new google.visualization.LineChart(document.getElementById('chart_div'));"

  invert_colors = true
  inverted_color_spec = ", backgroundColor: 'black', gridlineColor: '#444', legendTextStyle: { color: '#ccc' }, hAxis: { baselineColor: '#999', textStyle: { color: '#ccc' }, titleTextStyle: { color: '#ccc' } }, vAxis: { baselineColor: '#999', titleTextStyle: { color: '#ccc' }, textStyle: { color: '#ccc' } }"
  
  line_colors = "series: ["
  line_colors << SETS_TO_SHOW.map { |data_set| "{color: '#{@sets_config[data_set][:color]}'}" }.join(',')
  line_colors << "]"

  f.puts "chart.draw(data, { isStacked: false, lineWidth: 1, width: 1440, height: 800, #{line_colors} #{inverted_color_spec if invert_colors} });"
  f.puts "</script>"

f.puts <<END_HTML
  </body>
</html>
END_HTML

f.close
