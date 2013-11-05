#/usr/bin/env ruby

# Clear out any environment options.
if ARGV.first == '-e'
  ARGV.shift(2)
end

def numeric_arg_with_default(default_value)
  value = ARGV.shift
  if value =~ /\d/
    value.to_f
  else
    default_value
  end
end

hour_count = numeric_arg_with_default(6)
cloud = numeric_arg_with_default(1)
start_hour = numeric_arg_with_default(0)
point_count = numeric_arg_with_default(1440)

TIME_OFFSET = -7.hours
CLOUD_ID = cloud
ACCOUNT_ID = :all
# ACCOUNT_ID = 2370
EXCLUDE_LOW_PRIORITY = true
EXCLUDE_TEST_JOBS = true

DURATION = hour_count.hours
START_TIME = (start_hour == 0) ? (Time.now - DURATION) : (Time.now - start_hour.hours)
# START_TIME = Time.gm(2012,5,2,13,30,0)
DATA_POINTS = point_count
# DATA_POINTS = 6.hours / 15.seconds

all_data_sets = [:launched_workers, :active_workers, :bad_workers, :launched_worker_input_capacity, :active_worker_input_capacity, :bad_worker_input_capacity, :launched_worker_output_capacity, :active_worker_output_capacity, :bad_worker_output_capacity, :queued_inputs, :processing_inputs, :queued_outputs, :queued_output_load, :processing_outputs, :processing_output_load, :input_autoscale_threshold, :output_autoscale_threshold]
output_scaling_data_sets = [:launched_workers, :active_workers, :launched_worker_output_capacity, :output_autoscale_threshold, :active_worker_output_capacity, :queued_output_load, :processing_output_load]
input_scaling_data_sets = [:launched_workers, :active_workers, :launched_worker_input_capacity, :input_autoscale_threshold, :active_worker_input_capacity, :queued_inputs, :processing_inputs]

scale_analysis_sets = [:launched_worker_input_capacity, :input_autoscale_threshold, :active_worker_input_capacity, :queued_inputs, :processing_inputs, :launched_worker_output_capacity, :output_autoscale_threshold, :active_worker_output_capacity, :queued_output_load, :processing_output_load]
output_analysis_sets = [:launched_workers, :active_workers, :launched_worker_output_capacity, :output_autoscale_threshold, :active_worker_output_capacity, :queued_output_load, :processing_output_load]

account_job_analysis = [:queued_inputs, :processing_inputs, :queued_outputs, :queued_output_load, :processing_outputs, :processing_output_load]
account_job_analysis_without_capacities = [:queued_outputs, :processing_outputs, :queued_inputs, :processing_inputs]

simple_scale_analysis_sets_without_low_priority = [:launched_worker_input_capacity, :active_worker_input_capacity, :queued_inputs, :processing_inputs, :launched_worker_output_capacity, :active_worker_output_capacity, :output_autoscale_threshold, :active_worker_max_output_capacity, :queued_output_load, :processing_output_load]
simple_scale_analysis_sets = [:launched_worker_input_capacity, :active_worker_input_capacity, :queued_low_priority_inputs, :queued_inputs, :processing_inputs, :launched_worker_output_capacity, :active_worker_output_capacity, :output_autoscale_threshold, :active_worker_max_output_capacity, :queued_low_priority_output_load, :queued_output_load, :processing_output_load]

SETS_TO_SHOW = simple_scale_analysis_sets_without_low_priority
# SETS_TO_SHOW = simple_scale_analysis_sets

#####################################################################

@sets_config = {
  :launched_workers                => { :color => '#ccaa00', :capacity_scale => false, :desc => 'Launched Workers' },
  :active_workers                  => { :color => '#9999ff', :capacity_scale => false, :desc => 'Active Workers' },

  :bad_workers                     => { :color => '#663399', :capacity_scale => false, :desc => 'Bad Workers' },
  :bad_worker_input_capacity       => { :color => '#669900', :capacity_scale => false, :desc => 'Bad Worker Input Capacity' },
  :bad_worker_output_capacity      => { :color => '#66ffff', :capacity_scale => true,  :desc => 'Bad Worker Output Capacity' },

  :launched_worker_input_capacity  => { :color => '#CE341b', :capacity_scale => false, :desc => 'Launched Worker Input Capacity' },
  :active_worker_input_capacity    => { :color => '#DE4421', :capacity_scale => false, :desc => 'Active Worker Input Capacity' },
  :queued_inputs                   => { :color => '#993333', :capacity_scale => false, :desc => 'Queued Inputs' },
  :queued_low_priority_inputs      => { :color => '#993333', :capacity_scale => false, :desc => 'Queued Low Priority Inputs', :style => 'dashed' },
  :processing_inputs               => { :color => '#cc9999', :capacity_scale => false, :desc => 'Processing Inputs' },
  :input_autoscale_threshold       => { :color => '#cc0000', :capacity_scale => false, :desc => 'Input Autoscale Threshold' },

  :launched_worker_output_capacity => { :color => '#0066aa', :capacity_scale => true,  :desc => 'Launched Worker Output Capacity' },
  :active_worker_output_capacity   => { :color => '#00ccff', :capacity_scale => true,  :desc => 'Active Worker Output Capacity' },
  :launched_worker_max_output_capacity => { :color => '#E39024', :capacity_scale => true,  :desc => 'Launched Worker Output Max' },
  :active_worker_max_output_capacity   => { :color => '#FF9914', :capacity_scale => true,  :desc => 'Active Worker Output Max' },
  :queued_outputs                  => { :color => '#339966', :capacity_scale => false, :desc => 'Queued Outputs' },
  :queued_output_load              => { :color => '#33FF99', :capacity_scale => true,  :desc => 'Queued Output Load' },
  :queued_low_priority_output_load => { :color => '#33FF99', :capacity_scale => true,  :desc => 'Queued Low Priority Output Load', :style => 'dashed' },
  :processing_outputs              => { :color => '#99ffcc', :capacity_scale => false, :desc => 'Processing Outputs' },
  :processing_output_load          => { :color => '#9999cc', :capacity_scale => true,  :desc => 'Processing Output Load' },
  :output_autoscale_threshold      => { :color => '#6666cc', :capacity_scale => true,  :desc => 'Output Autoscale Threshold' },
}

@start_time = START_TIME
@end_time = START_TIME + DURATION
@worker_types = {}
@cloud = Cloud.find(CLOUD_ID)
@cloud.machine_types.all.each { |wt| @worker_types[wt.id] = wt }

puts "#{Time.now} Querying database for data..."

@workers = @cloud.workers.find(:all, :select => 'id,machine_type_id,state,created_at,alive_at,killed_at,updated_at,last_heartbeat_at,url,instance_id', :conditions => ["(killed_at >= ? OR (killed_at is null AND updated_at >= ?)) AND created_at < ?", @start_time, @start_time, @end_time])
if ACCOUNT_ID != :all
  raise "Not yet optimized."
  @inputs = @cloud.input_media_files.find(:all, :select => 'id,account_id,job_id,state,created_at,started_at,finished_at,times,low_priority', :conditions => ["(finished_at is null or finished_at >= ?) and created_at < ? and state != 'cancelled' and account_id = ?", @start_time, @end_time, ACCOUNT_ID])
  @outputs = @cloud.output_media_files.find(:all, :select => 'id,account_id,job_id,state,created_at,started_at,updated_at,finished_at,times,low_priority,cached_queue_time,cached_total_time,estimated_transcode_load', :conditions => ["(finished_at is null or finished_at >= ?) and created_at < ? and state != 'cancelled' and account_id = ?", @start_time, @end_time, ACCOUNT_ID])
elsif false
  # Use this for disabling input/output collection.  Just for fast counts of worker info.
  @inputs = []
  @outputs = []
else
  before = Time.now
  running_inputs =  @cloud.input_media_files.find(:all, :select => 'id,account_id,job_id,state,created_at,started_at,finished_at,times,low_priority,test', :conditions => ["finished_at is null and created_at < ? and state != 'cancelled'", @end_time])
  puts "  Got #{running_inputs.length} running inputs. (#{Time.now-before} seconds)"

  before = Time.now
  finished_inputs = @cloud.input_media_files.find(:all, :select => 'id,account_id,job_id,state,created_at,started_at,finished_at,times,low_priority,test', :conditions => ["finished_at >= ? and finished_at <= ? and created_at < ? and state != 'cancelled'", @start_time, @end_time + 3.hours, @end_time])
  puts "  Got #{finished_inputs.length} finished inputs. (#{Time.now-before} seconds)"

  before = Time.now
  in_finished_set = {}
  finished_inputs.each { |f| in_finished_set[f.id] = true }
  running_inputs.delete_if { |r| in_finished_set[r.id] }
  @inputs = running_inputs + finished_inputs
  puts "  Combined inputs. (#{Time.now-before} seconds)"


  before = Time.now
  running_outputs =  @cloud.output_media_files.find(:all, :select => 'id,account_id,job_id,state,created_at,started_at,updated_at,finished_at,times,low_priority,test,cached_queue_time,cached_total_time,estimated_transcode_load', :conditions => ["finished_at is null and created_at < ? and state = 'processing'", @end_time])
  puts "  Got #{running_outputs.length} running outputs. (#{Time.now-before} seconds)"

  before = Time.now
  finished_outputs = @cloud.output_media_files.find(:all, :select => 'id,account_id,job_id,state,created_at,started_at,updated_at,finished_at,times,low_priority,test,cached_queue_time,cached_total_time,estimated_transcode_load', :conditions => ["finished_at >= ? and finished_at <= ? and created_at < ? and state != 'cancelled'", @start_time, @end_time + 3.hours, @end_time])
  puts "  Got #{finished_outputs.length} finished outputs. (#{Time.now-before} seconds)"

  before = Time.now
  in_finished_set = {}
  finished_outputs.each { |f| in_finished_set[f.id] = true }
  running_outputs.delete_if { |r| in_finished_set[r.id] }
  @outputs = running_outputs + finished_outputs
  puts "  Combined outputs. (#{Time.now-before} seconds)"
end

puts "#{Time.now} Queries finished."

before = Time.now
@worker_time_data = []
@workers.each do |worker|
  next unless worker.instance_id.present? # Filter out bad calls to amazon.

  # For now we ignore all debugging/stopped/etc workers.
  next unless worker.killed_at || ['launching','active','terminating','updating','disappeared'].include?(worker.state)

  input_capacity = @worker_types[worker.machine_type_id].max_downloads || 6
  output_capacity = @worker_types[worker.machine_type_id].target_load || 900
  max_output_capacity = @worker_types[worker.machine_type_id].max_load || output_capacity

  created = worker.created_at.to_i
  updated = worker.updated_at.to_i

  # Try to account for ones that got updated (so their alive_at is not when they actually launched), and just
  # use a bit after the created_at time.
  if worker.alive_at && (worker.alive_at - worker.created_at > 30.minutes)
    alive = created + 4.minutes
  else
    alive = (worker.alive_at || Time.now + 1.year).to_i
  end

  if worker.state == 'disappeared'
    killed = (worker.killed_at || worker.last_heartbeat_at || worker.updated_at || Time.now + 1.year).to_i
  else
    killed = (worker.killed_at || Time.now + 1.year).to_i
  end

  if worker.url.blank? && ['terminated','disappeared'].include?(worker.state)
    @worker_time_data << { :type => :bad_launch, :time => created, :input_capacity => input_capacity, :output_capacity => output_capacity, :max_output_capacity => max_output_capacity }
    @worker_time_data << { :type => :bad_kill,   :time => updated, :input_capacity => input_capacity, :output_capacity => output_capacity, :max_output_capacity => max_output_capacity }
  elsif worker.url.present? || ['launching'].include?(worker.state)
    # Good worker.
    @worker_time_data << { :type => :launched, :time => created, :input_capacity => input_capacity, :output_capacity => output_capacity, :max_output_capacity => max_output_capacity }
    @worker_time_data << { :type => :active,   :time => alive,   :input_capacity => input_capacity, :output_capacity => output_capacity, :max_output_capacity => max_output_capacity }
    @worker_time_data << { :type => :killed,   :time => killed,  :input_capacity => input_capacity, :output_capacity => output_capacity, :max_output_capacity => max_output_capacity }
  else
    puts "Ignoring bad worker record - #{worker.id}"
  end

end
@worker_time_data = @worker_time_data.sort_by { |d| d[:time] }
puts "Loaded worker data... (#{Time.now-before} seconds)"

before = Time.now
# @input_total_times = {}
@input_finish_times = {} # By job ID.
@input_time_data = []
@inputs.each do |input|
  next unless input.finished_at || ['waiting','processing'].include?(input.state)
  next if EXCLUDE_LOW_PRIORITY && input.low_priority
  next if EXCLUDE_TEST_JOBS && input.test?

  @input_time_data << { :type => :queued, :time => input.created_at.to_i, :low_priority => input.low_priority }
  @input_time_data << { :type => :started, :time => (input.started_at || Time.now + 1.year).to_i, :low_priority => input.low_priority }
  @input_time_data << { :type => :finished, :time => (input.finished_at || Time.now + 1.year).to_i, :low_priority => input.low_priority }

  @input_finish_times[input.job_id.to_i] = input.finished_at
  # @input_total_times[input.id] = input.total_time rescue nil
end
@input_time_data = @input_time_data.sort_by { |d| d[:time] }
puts "Loaded input data... (#{Time.now-before} seconds)"

before = Time.now
@output_time_data = []
@outputs.each do |output|
  next if output.state == 'no_input'
  next if output.state == 'skipped'
  next unless output.finished_at || ['ready','processing','uploading'].include?(output.state)
  # next if EXCLUDE_LOW_PRIORITY && output.low_priority
  next if EXCLUDE_TEST_JOBS && output.test?

  # Will figure this out later too.
  # next if output.state == 'failed'
  
  if output.finished_at.nil?
    if output.state == 'ready'
      processing_start = Time.now + 1.year
      queue_start = output.updated_at
    elsif ['processing','uploading'].include?(output.state)
      processing_start = output.started_at || output.updated_at
      queue_start = @input_finish_times[output.job_id.to_i] || output.created_at
    else
      puts "Don't know what to do with output #{output.id} that is not finished and has state #{output.state}!"
    end
  else
    processing_start = output.started_at || (output.finished_at - (output.transcode_time.to_f + output.upload_time.to_f))

    if output.cached_queue_time
      queue_start = processing_start - output.cached_queue_time.to_f
    else
      queue_start = @input_finish_times[output.job_id.to_i]
      if !queue_start
        puts "Don't know what to do with output #{output.id} -- no queue start time!"
        next
      end
    end
  end

  load = output.estimated_transcode_load || 200

  @output_time_data << { :type => :queued, :time => queue_start.to_i, :load => load, :low_priority => output.low_priority }
  @output_time_data << { :type => :started, :time => processing_start.to_i, :load => load, :low_priority => output.low_priority }
  @output_time_data << { :type => :finished, :time => (output.finished_at || Time.now + 1.year).to_i, :load => load, :low_priority => output.low_priority }
end
@output_time_data = @output_time_data.sort_by { |d| d[:time] }
puts "Loaded output data... (#{Time.now-before} seconds)"

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
    if @sets_config[data_set][:desc] =~ /low priority/i
      f.puts "data.addColumn({type:'boolean',role:'certainty'})"
    end
  end

  f.puts "data.addRows(["


  # Initialize all set data points to an array with an intitial zero.
  @data_points = { }
  @sets_config.keys.each { |k| @data_points[k] = [0] }

  # Initialize all baselines to zero.
  @baselines = { }
  @sets_config.keys.each { |k| @baselines[k] = 0 }
  
  @granularity = (@end_time - @start_time) / DATA_POINTS.to_f

  puts "Analyzing..."
  ############# SET UP WORKER DATA ##############
  before = Time.now
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
        @baselines[:launched_worker_max_output_capacity] += data[:max_output_capacity]
        @baselines[:input_autoscale_threshold] += data[:input_capacity] * 1.2
        @baselines[:output_autoscale_threshold] += data[:output_capacity] * 1.2
      when :active
        @baselines[:active_workers] += 1
        @baselines[:active_worker_input_capacity] += data[:input_capacity]
        @baselines[:active_worker_output_capacity] += data[:output_capacity]
        @baselines[:active_worker_max_output_capacity] += data[:max_output_capacity]
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

    point_loc = DATA_POINTS + 1 if point_loc > DATA_POINTS

    while prev_point < point_loc
      [:launched_workers, :launched_worker_input_capacity, :launched_worker_output_capacity, :launched_worker_max_output_capacity,
       :active_workers, :active_worker_input_capacity, :active_worker_output_capacity, :active_worker_max_output_capacity,
       :bad_workers, :bad_worker_input_capacity, :bad_worker_output_capacity,
       :input_autoscale_threshold, :output_autoscale_threshold].each do |data_set|
        @data_points[data_set][prev_point + 1] = @data_points[data_set][prev_point]
      end
      prev_point += 1
    end

    next if point_loc > DATA_POINTS

    case data_type
    when :launched
      @data_points[:launched_workers][point_loc] += 1
      @data_points[:launched_worker_input_capacity][point_loc] += data[:input_capacity]
      @data_points[:launched_worker_output_capacity][point_loc] += data[:output_capacity]
      @data_points[:launched_worker_max_output_capacity][point_loc] += data[:max_output_capacity]
      @data_points[:input_autoscale_threshold][point_loc] += data[:input_capacity] * 1.2
      @data_points[:output_autoscale_threshold][point_loc] += data[:output_capacity] * 1.2
    when :active
      @data_points[:active_workers][point_loc] += 1
      @data_points[:active_worker_input_capacity][point_loc] += data[:input_capacity]
      @data_points[:active_worker_output_capacity][point_loc] += data[:output_capacity]
      @data_points[:active_worker_max_output_capacity][point_loc] += data[:max_output_capacity]
    when :killed
      @data_points[:launched_workers][point_loc] -= 1
      @data_points[:launched_worker_input_capacity][point_loc] -= data[:input_capacity]
      @data_points[:launched_worker_output_capacity][point_loc] -= data[:output_capacity]
      @data_points[:launched_worker_max_output_capacity][point_loc] -= data[:max_output_capacity]
      @data_points[:input_autoscale_threshold][point_loc] -= data[:input_capacity] * 1.2
      @data_points[:output_autoscale_threshold][point_loc] -= data[:output_capacity] * 1.2
      @data_points[:active_workers][point_loc] -= 1
      @data_points[:active_worker_input_capacity][point_loc] -= data[:input_capacity]
      @data_points[:active_worker_output_capacity][point_loc] -= data[:output_capacity]
      @data_points[:active_worker_max_output_capacity][point_loc] -= data[:max_output_capacity]
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
  puts "  Worker analysis done. (#{Time.now-before} seconds)"

  ############# SET UP INPUTS DATA ##############
  before = Time.now
  prev_point = 0
  queued_subtractions = 0
  queued_low_priority_subtractions = 0
  @input_time_data.each do |data|
    data_type = data[:type]

    # For events before the graph, just update the baselines.
    if data[:time] < @start_time.to_i
      case data_type
      when :queued
        @baselines[:queued_inputs] += 1 unless data[:low_priority]
        @baselines[:queued_low_priority_inputs] += 1
      when :started
        @baselines[:processing_inputs] += 1
      end

      next
    end

    offset = data[:time] - @start_time.to_i
    point_loc = (offset / @granularity).round

    point_loc = DATA_POINTS + 1 if point_loc > DATA_POINTS

    while prev_point < point_loc
      [:queued_inputs].each do |data_set|
        @data_points[data_set][prev_point + 1] = @data_points[data_set][prev_point] - queued_subtractions
      end
      [:queued_low_priority_inputs, :processing_inputs].each do |data_set|
        @data_points[data_set][prev_point + 1] = @data_points[data_set][prev_point] - queued_low_priority_subtractions
      end
      queued_subtractions = 0
      queued_low_priority_subtractions = 0
      prev_point += 1
    end
    
    next if point_loc > DATA_POINTS

    case data_type
    when :queued
      @data_points[:queued_inputs][point_loc] += 1 unless data[:low_priority]
      @data_points[:queued_low_priority_inputs][point_loc] += 1
    when :started
      @data_points[:processing_inputs][point_loc] += 1
    when :finished
      queued_subtractions += 1 unless data[:low_priority]
      queued_low_priority_subtractions += 1
    end
  end
  puts "  Input analysis done. (#{Time.now-before} seconds)"

  ############# SET UP OUPUTS DATA ##############
  before = Time.now
  prev_point = 0
  queued_subtractions = 0
  queued_load_subtractions = 0
  queued_low_priority_load_subtractions = 0
  @output_time_data.each do |data|
    data_type = data[:type]

    # For events before the graph, just update the baselines.
    if data[:time] < @start_time.to_i
      case data_type
      when :queued
        @baselines[:queued_outputs] += 1
        @baselines[:queued_output_load] += data[:load] unless data[:low_priority]
        @baselines[:queued_low_priority_output_load] += data[:load]
      when :started
        @baselines[:processing_outputs] += 1
        @baselines[:processing_output_load] += data[:load]
      end

      next
    end

    offset = data[:time] - @start_time.to_i
    point_loc = (offset / @granularity).round

    point_loc = DATA_POINTS + 1 if point_loc > DATA_POINTS

    while prev_point < point_loc
      [:queued_outputs, :processing_outputs].each do |data_set|
        @data_points[data_set][prev_point + 1] = @data_points[data_set][prev_point] - queued_subtractions
      end
      [:queued_output_load].each do |data_set|
        @data_points[data_set][prev_point + 1] = @data_points[data_set][prev_point] - queued_load_subtractions
      end
      [:queued_low_priority_output_load, :processing_output_load].each do |data_set|
        @data_points[data_set][prev_point + 1] = @data_points[data_set][prev_point] - queued_low_priority_load_subtractions
      end
      queued_subtractions = 0
      queued_load_subtractions = 0
      queued_low_priority_load_subtractions = 0
      prev_point += 1
    end
    
    next if point_loc > DATA_POINTS

    case data_type
    when :queued
      @data_points[:queued_outputs][point_loc] += 1
      @data_points[:queued_output_load][point_loc] += data[:load] unless data[:low_priority]
      @data_points[:queued_low_priority_output_load][point_loc] += data[:load]
    when :started
      @data_points[:processing_outputs][point_loc] += 1
      @data_points[:processing_output_load][point_loc] += data[:load]
    when :finished
      queued_subtractions += 1
      queued_load_subtractions += data[:load] unless data[:low_priority]
      queued_low_priority_load_subtractions += data[:load]
    end
  end
  puts "  Output analysis done. (#{Time.now-before} seconds)"

  # ############# SCALE DOWN OUTPUT LOAD ###########
  # max_outputs = [
  #   @data_points[:queued_outputs].max + @baselines[:queued_outputs],
  #   @data_points[:processing_outputs].max + @baselines[:processing_outputs],
  # ].max
  # max_capacity = [
  #   @data_points[:launched_worker_output_capacity].max + @baselines[:launched_worker_output_capacity],
  #   @data_points[:active_worker_output_capacity].max + @baselines[:active_worker_output_capacity],
  #   @data_points[:bad_worker_output_capacity].max + @baselines[:bad_worker_output_capacity],
  # ].max
  # scale = max_outputs.to_f / max_capacity
  # 
  # [:queued_output_load, :launched_worker_output_capacity, :processing_output_load, :active_worker_output_capacity, :bad_worker_output_capacity].each do |data_set|
  #   @baselines[data_set] = (@baselines[data_set] * scale).round
  #   @data_points[data_set].each_with_index do |value,index|
  #     @data_points[data_set][index] = (value * scale).round
  #   end
  # end
  # puts "  Scaled results."

  before = Time.now
  puts "Building output..."
  DATA_POINTS.times do |p|
    if DURATION <= 1.hour
      time = (@start_time + (p*@granularity) + TIME_OFFSET).strftime('%H:%M:%S')
    else
      time = (@start_time + (p*@granularity) + TIME_OFFSET).strftime('%H:%M')
    end
    values = []
    SETS_TO_SHOW.each do |data_set|
      values << (@baselines[data_set].to_f + @data_points[data_set][p].to_f).round
      if @sets_config[data_set][:desc] =~ /low priority/i
        values << 'false'
      end
    end
    f.puts "  ['%s', %s]," % [time, values.join(',')]
  end
  puts "Done. (#{Time.now-before} seconds)"
  
  f.puts "]);"
  f.puts "var chart = new google.visualization.LineChart(document.getElementById('chart_div'));"

  
  chart_specs = []
  # Basics
  chart_specs << "isStacked: false, lineWidth: 1, width: #{DATA_POINTS + 200}, height: 800"
  # Layout
  chart_specs << "chartArea: { width: #{DATA_POINTS} }"
  # Overall colors
  chart_specs << "backgroundColor: 'black', gridlineColor: '#444', legendTextStyle: { color: '#ccc', fontSize: 10 }, hAxis: { baselineColor: '#999', textStyle: { color: '#ccc' }, titleTextStyle: { color: '#ccc' } }, vAxis: { baselineColor: '#999', titleTextStyle: { color: '#ccc' }, textStyle: { color: '#ccc' } }"
  # Vertical axes
  chart_specs << "vAxes:[{title:'Actual Values', minValue:0},{title:'Capacities/Loads', minValue:0}]"

  # Line colors
  line_colors = "series: ["
  line_colors << SETS_TO_SHOW.map { |data_set| "{color: '#{@sets_config[data_set][:color]}', targetAxisIndex: #{@sets_config[data_set][:capacity_scale] ? 1 : 0}}" }.join(',')
  line_colors << "]"
  chart_specs << line_colors

  f.puts "chart.draw(data, { #{chart_specs.join(', ')} });"
  f.puts "</script>"

f.puts <<END_HTML
  </body>
</html>
END_HTML

f.close

