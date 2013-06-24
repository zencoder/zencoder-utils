#/usr/bin/env ruby

# File: live_job_latency_grapher.rb
# Authors: Justin Greer, Scott Kidder
# Purpose: Generates an HTML page containing interactive charts for the 
#          processing latency values associated with a Live job outputs.
# Usage: 
# 1) Add the following Bash functions to your ~/.bashrc file:
#  LIVE_SCRIPT_LOCATION=${HOME}/git/zencoder-utils/live_job_latency_grapher.rb
#   function finished_live_job_graph {
#     scp $LIVE_SCRIPT_LOCATION util2:
#     ssh util2 "cd /data/zencoder/current_db4; script/runner -e production ~/live_job_latency_grapher.rb --user $USER $1"
#     scp util2:/data/zencoder/current_db4/live_job_latency_graph.html /tmp/
#     open /tmp/live_job_latency_graph.html
#    }
#   function running_live_job_graph {
#     scp $LIVE_SCRIPT_LOCATION util2:
#     ssh util2 "cd /data/zencoder/current_db4; script/runner -e production ~/live_job_latency_grapher.rb --live --user $USER $1"
#     scp util2:/data/zencoder/current_db4/live_job_latency_graph.html /tmp/
#     open /tmp/live_job_latency_graph.html
#   }
#
# 2) Ensure that the .bashrc file has been sourced so that the functions are 
#    available in your current Bash shell
#
# 3) Run the script for a Live job using the job ID:
#      Completed job:     finished_live_job_graph <job ID>
#      Running job:       running_live_job_graph <job ID>
#
# 

require 'thread'
require 'digest'

def numeric_arg_with_default(default_value)
  value = ARGV.shift
  if value =~ /\d/
    value.to_f
  else
    default_value
  end
end

def worker_dir_for(kind, file_id)
  sum = Digest::SHA1.hexdigest(file_id.to_s)
  "/data/tmp/zencoder/%s/%s/%s/%s/%s/%d" % [kind.to_s, sum[0,1], sum[1,2], sum[3,2], sum[5,2], file_id.to_i]
end

def create_local_filename
  '/tmp/log_' + Digest::MD5.hexdigest((Kernel.rand * 1e10).to_s)
end

# Escape single-quotes in filenames so they can't mess up the command-line. 
def escape_for_single_quotes(filename)
  # Turn single quotes into: '\''
  #   The shell takes that as "end string", "apostrophe", and "start string", but concatenates
  #   strings that touch, so it works out in the end.
  #   Also, have to extra-escape backslashes in replacements since Ruby looks for \1, \2, etc.
  filename.gsub("'","'\\\\''")
end

def shell_escape(filename)
  "'" + escape_for_single_quotes(filename) + "'"
end

def get_stored_log(media_file, kind, path)
  log_urls = Zencoder::FileLogLister.new(media_file).list
  log_url = log_urls.detect { |lu| lu.url.include?(path) }
  if !log_url
    puts "No stored log files found for #{kind} #{media_file.id} -- skipping!"
    return nil
  end

  local_name = create_local_filename
  local_gzip_name = local_name + '.gz'

  authenticated = log_url.url.to_zu.authenticate
  command = "curl --insecure -o #{local_gzip_name} #{shell_escape(authenticated)} 2>&1"
  puts "Getting stored log: #{command}"
  result = `#{command}`

  if !File.exist?(local_gzip_name)
    puts "Couldn't retrieve stored log file for #{kind} #{media_file.id} -- skipping: \n***************************************\n#{result}***************************************\n"
    return nil
  end

  `gzip -dc #{local_gzip_name} > #{local_name}`
  `rm #{local_gzip_name}`

  puts "................................................................."

  local_name
end

def get_live_log(media_file, kind, path)
  worker = media_file.worker
  if !worker
    puts "No worker for #{kind} #{media_file.id} -- skipping!"
    return nil
  end
  partial_path = worker_dir_for(kind, media_file.id)

  command = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null #{shell_escape(@ssh_user)}@#{shell_escape(worker.hostname)} \"find #{shell_escape(partial_path)} -maxdepth 2 -type d | sort | tail -1\" 2>&1"
  puts "Getting dir for live log log: #{command}"
  result = `#{command}`

  working_dir = result.split(/\n/).detect { |line| line.to_s.include?(media_file.id.to_s) }
  if !working_dir
    puts "Live log dir not found for #{kind} #{media_file.id} -- skipping!"
    return nil
  end

  full_path = File.join(working_dir.to_s.strip, path)
  local_name = create_local_filename

  command = "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null #{shell_escape(@ssh_user)}@#{shell_escape(worker.hostname)}:#{shell_escape(full_path)} #{local_name} 2>&1"
  puts "Getting live log: #{command}"
  result = `#{command}`

  if !File.exist?(local_name)
    puts "Couldn't find/get live log file for #{kind} #{media_file.id} -- skippping: \n***************************************\n#{result}***************************************\n"
    return nil
  end

  puts "................................................................."

  local_name
end

def get_log(media_file, kind, path)
  if @job_is_live
    get_live_log(media_file, kind, path)
  else
    get_stored_log(media_file, kind, path)
  end
end

#####################################################
#####################################################
#####################################################


@graph_names = {}
@graph_count = 0

def start_html_output
  @output_stream.puts '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta http-equiv="content-type" content="text/html; charset=utf-8" />
  <script type="text/javascript" src="https://zencodertesting.s3.amazonaws.com/justin/dygraph-combined.js"></script>
  <script type="text/javascript" src="https://www.google.com/jsapi"></script>
  <script type="text/javascript">'

  @output_stream.puts "  google.load('visualization', '1', {packages: ['annotatedtimeline']});"
  @output_stream.puts "  var g;"
  @output_stream.puts "  var rtmp_data_set = new Array();"
  @output_stream.puts "  var encode_data_set = new Array();"
  @output_stream.puts "  var rtmp_event_data_set = new Array();"
  @output_stream.puts "  var encode_event_data_set = new Array();"
  @output_stream.puts
  @output_stream.puts "  function drawVisualization() {"
end




# Close out the JavaScript block and add output-selection controls.
def finish_html_output

  @output_stream.puts
  @output_stream.puts "    g = new Dygraph(document.getElementById(\"visualization\"));"
  @output_stream.puts "    update_graph(2);"
  @output_stream.puts "  }"
  @output_stream.puts
  @output_stream.puts "  google.setOnLoadCallback(drawVisualization);"
  @output_stream.puts

  @output_stream.puts '  </script>
</head>
<body style="font-family: Arial;border: 0 none;">'
  @output_stream.puts "<h2>Job #{@job_id} Live Stream Latency (#{@job_is_live ? 'Currently Streaming' : 'Finished'})</h2>"
  @output_stream.puts '<div id="visualization" style="width: 100%; height: 400px;"></div>'
  @output_stream.puts " <p><b>Show Series:</b></p>
    <p>"

  2.upto(@graph_count) do |i|
    @output_stream.puts " <input type=\"radio\" name=\"outputs\" id=\"#{i}\" onClick=\"change(this)\" #{i == 2 ? "checked=\"checked\"" : ""}><label for=\"#{i}\">#{@graph_names[i]}</label><br/>"
  end

  @output_stream.puts "<script type=\"text/javascript\">
      function change(el) {
        update_graph(el.id);
      }

      function update_graph(i) {
        // combine the RTMP input & RTMP output streams
        if ((rtmp_data_set[1] != undefined) && (rtmp_data_set[i] != undefined)) {
          var merged_data = google.visualization.data.join(rtmp_data_set[1], rtmp_data_set[i], 'full', [[0,0]], [1], [1]);

          // If worker latency logs are available, throw those in as well
          if (encode_data_set[i] != undefined) {
            merged_data = google.visualization.data.join(merged_data, encode_data_set[i], 'full', [[0,0]], [1,2], [1]);
          }

          g.updateOptions({ 'file': merged_data, connectSeparatedPoints: true, legend: 'always', axisLabelFontSize: 12, displayAnnotations: true, showRangeSelector: true, valueRange: [0,null] } );
          var merged_annotations = rtmp_event_data_set[1].concat(rtmp_event_data_set[i]).concat(encode_event_data_set[i]);
          g.setAnnotations(merged_annotations);
        }
      }
      </script>"
  @output_stream.puts '</body>
</html>'
end

module LogBase

  # Output the data-set for a given log file.  All output will be sent to the 
  # object referenced by the output' parameter.
  #
  def output_graph_data(title,graph_id,log_type,log,output)

    # EVENT DATA
    # Concatenate the event labels since Dygraph doesn't support multiple 
    # annotations at a single x-axis point
    annotation_labels = Hash.new
    log.events.each do |event|

      # round the timestamp to whole seconds since Dygraph does not support 
      # annotations with millisecond-or-finer precision
      current_timestamp = Time.at(event[0].to_f.round)
      if annotation_labels.key?(current_timestamp) then
        annotation_labels[current_timestamp] << ", #{event[1].to_s}"
      else
        annotation_labels[current_timestamp] = "#{event[1].to_s}"
      end
    end

    # iterate over the events and send them to output
    event_timestamp_hash = Hash.new
    output.puts "    #{log_type}_event_data_set[#{graph_id}] = ["
    annotation_labels.keys.each do |event_timestamp|
      # add entry to the timestamp map for lookup when processing the RTMP logs
      event_timestamp_hash[event_timestamp] = "default"

      output.puts "{"
      output.puts "series: \"#{title}-#{log_type}\","
      output.puts "x: \"%s\"," % event_timestamp.strftime("%F %TZ")
      output.puts "shortText: \"%s\"," % annotation_labels[event_timestamp]
      output.puts "text: \"%s\"," % annotation_labels[event_timestamp]
      output.puts "},"
    end
    output.puts "    ];"
    output.puts

    # TIMING DATA
    output.puts "    // debug: stream_start_delay=#{log.stream_start_delay}
                     // debug: max_start_offset=#{log.max_start_offset}
                     // debug: stream_start_time=#{log.stream_start_time}
                     var data_#{log_type}_#{graph_id} = new google.visualization.DataTable();
                     data_#{log_type}_#{graph_id}.addColumn('datetime', 'Time');
                     data_#{log_type}_#{graph_id}.addColumn('number', '#{title}-#{log_type}');
                     data_#{log_type}_#{graph_id}.addRows(["

    assumed_stream_baseline = log.stream_start_time - [log.stream_start_delay, log.max_start_offset / 1000.0].max
    log.timings.each do |timing|
      latency = (timing[0] - assumed_stream_baseline)-(timing[2]/1000.0)
      output.puts "[new Date(%d), %0.3f]," % [(timing[0].to_f * 1000).round, (latency < 0.0 ? 0 : latency)]

      if event_timestamp_hash[Time.at(timing[0].to_f.round)] == "default" then
        output.puts "[new Date(%d), %0.3f]," % [timing[0].to_f.round * 1000, (latency < 0.0 ? 0 : latency)]
        event_timestamp_hash[Time.at(timing[0].to_f.round)] = "complete"
      end
    end
    output.puts "    ]);"

    # add the output data set to an array indexed by the graph-id for look-up
    # when an output is selected in the UI
    output.puts "    #{log_type}_data_set[#{graph_id}] = data_#{log_type}_#{graph_id};"
  end
end


# Collection of input stream logs on a Stream Ingest worker node
#
class IngestLogs
  include LogBase

  attr_accessor :download_log, :parsed_download_log

  def initialize(download_log)
    @download_log = download_log
    @parsed_download_log = RTMPLog.new(download_log)
  end

  def valid?
    return @parsed_download_log.valid?
  end

  def analyze(key, graph_id, output)
    output_graph_data(key,graph_id,"rtmp",@parsed_download_log, output)
  end

  def cleanup
    File.unlink(@download_log) if @download_log
  end
end


# Collection of job logs for a single output on an Encoding Worker node
#
class WorkerLogs
  include LogBase

  attr_accessor :upload_log, :encode_log, :parsed_upload_log, :parsed_encode_log

  def initialize(upload_log, encode_log)
    @upload_log = upload_log
    @encode_log = encode_log

    @parsed_upload_log = RTMPLog.new(upload_log)
    @parsed_encode_log = WorkerEncodeLatencyLog.new(encode_log)
  end

  def valid?
    return @parsed_upload_log.valid?
  end

  def analyze(key, graph_id, output)
    output_graph_data(key,graph_id,"rtmp",@parsed_upload_log, output)

    if @parsed_encode_log.valid?
      output_graph_data(key,graph_id,"encode",@parsed_encode_log, output)
    end
  end

  def cleanup
    File.unlink(@upload_log) if @upload_log
    File.unlink(@encode_log) if @encode_log
  end
end


# Parser for the Worker Encode Latency log file.  Provides accessors to events,
# stream timing, and other metrics.
# 
class WorkerEncodeLatencyLog
  attr_accessor :stream_start_time, :stream_start_delay, :max_start_offset, :timings, :max_stream_time, :max_latency, :events
  
  def initialize(filename)
    @filename = filename
    parse_log_data if valid?
  end

  def valid?
    return !!@valid unless @valid.nil?
    @valid = log_is_encode_worker_latency?
  end
  
  def log_is_encode_worker_latency?
    return nil if @filename.nil?

    # Just check if the first bit of the log includes "transcoding"
    data = File.read(@filename, 2048)
    data.to_s.include?("encode")
  end

  def parse_timestamp(line)
    if line =~ /\[(\d+-\d+-\d+ \d+:\d+:\d+\.\d+)\]/
      Time.parse($1 + ' -0000')
    end
  end

  def parse_log_data
    logfile = File.open(@filename, 'r')

    @events = []
    @timings = []
    @max_start_offset = 0
    @line_count = 0
    @stream_start_delay = 0
    @stream_start_time = nil
    @last_stream_time = 0


    while line = logfile.gets
      @line_count += 1
      # Ignore comments
      next if line =~ /^#/
      # line_timestamp = parse_timestamp(line)

      case line
        when /^(.+) INFO -- (.+)$/

          # parse the JSON data from the log line
          log_stats = eval($2)

          if log_stats['encode'] != nil then

            cur_time = log_stats['encode']['cur_time'].to_f
            if @stream_start_time.nil? then
              @stream_start_time = log_stats['encode']['start_time'].to_f
              @events << [cur_time, :started_encoding]
            end
            @last_stream_time = log_stats['encode']['stream_time'].to_f * 1000
            @timings << [cur_time, @stream_start_time, @last_stream_time, nil]
          end
        end
      end
      logfile.close

      # look for the baseline in the collected timing info
      prev_cur_time = nil
      prev_stream_time = nil
      @timings.each do |timing|
        cur_time = timing[0]
        stream_time = (timing[2] / 1000)

        # if it's the first pass
        if prev_cur_time.nil?
          prev_cur_time = cur_time
          prev_stream_time = stream_time
        else
          # only evaluate cases where the difference between timestamps is more than one second
          cur_time_delta = cur_time - prev_cur_time
          if (cur_time_delta > 0.5)
            if cur_time_delta > (stream_time - prev_stream_time)
              # found the baseline, where we're transcoding slower than realtime
              # e.g. wall clock time that's passed is greater than the stream time that's passed
              @stream_start_time = cur_time - stream_time
              break
            end

            prev_stream_time = stream_time
            prev_cur_time = cur_time
          end
        end
      end
    end
  end



# Parser for the RTMP upload/download log files.  Provides accessors to events,
# stream timing, and other metrics.
#
class RTMPLog
  attr_accessor :stream_start_time, :stream_start_delay, :max_start_offset, :timings, :max_stream_time, :max_latency, :events
  
  def initialize(filename)
    @filename = filename
    parse_log_data if valid?
  end

  def valid?
    return !!@valid unless @valid.nil?
    @valid = log_is_rtmp?
  end
  
  def log_is_rtmp?
    return nil if @filename.nil?
    # Just check if the first bit of the log includes "RTMP" (usually occurs around 600-650 bytes in)
    data = File.read(@filename, 2048)
    data.to_s.include?("RTMP")
  end

  def parse_timestamp(line)
    if line =~ /\[(\d+-\d+-\d+ \d+:\d+:\d+\.\d+)\]/
      Time.parse($1 + ' -0000')
    end
  end

  def parse_log_data
    logfile = File.open(@filename, 'r')

    @events = []
    @timings = []
    @first_timestamp_seen = nil
    @last_timestamp_seen = nil
    @max_start_offset = 0
    @line_count = 0
    @stream_start_delay = 0
    @stream_start_time = nil
    @last_stream_time = 0


    while line = logfile.gets
      @line_count += 1
      next if line =~ /^#/
      line_timestamp = parse_timestamp(line)
      @first_timestamp_seen ||= line_timestamp
      @last_timestamp_seen = line_timestamp

      case line
        when /WARNING: Auth failed/
          @events << [line_timestamp, :auth_failed]
          @timings << [line_timestamp, stream_start_time, @last_stream_time, nil]
        when /DEBUG: Invoking FCPublish/
          @events << [line_timestamp, :fc_publish]
          @timings << [line_timestamp, stream_start_time, @last_stream_time, nil]

        when /INFO: STREAM_START (\d+)/
          stream_start_time = $1.to_i
          @last_stream_time = 0
          @stream_start_time = line_timestamp
          @stream_start_delay = (line_timestamp - @first_timestamp_seen)
          @events << [line_timestamp, :started_streaming]
          @timings << [line_timestamp, stream_start_time, 0, nil]
          @last_time = line_timestamp
        when /DEBUG: New start time offset: (\d+)/
          @max_start_offset = $1.to_i
        when /INFO: TIME (\d+) OFFSET (\d+) STREAM_TIME (\d+)/
          time,offset,stream_time = [$1.to_i, $2.to_i, $3.to_i]
          @timings << [line_timestamp, time, stream_time, nil]
          @last_time = time
          @last_stream_time = stream_time
        when /WARNING: WriteN, RTMP send error/
          @events << [line_timestamp, :send_error]
          @timings << [line_timestamp, stream_start_time, @last_stream_time, nil]
        when /ERROR: disconnected from remote server/
          @events << [line_timestamp, :disconnect]
          @timings << [line_timestamp, stream_start_time, @last_stream_time, nil]
        when /INFO: send_data, done sending/
          @events << [line_timestamp, :done]
          @timings << [line_timestamp, stream_start_time, @last_stream_time, nil]
        end
      end

      logfile.close

      assumed_stream_baseline = @stream_start_time - [@stream_start_delay, @max_start_offset / 1000.0].max

      @max_latency = 0.0
      @max_stream_time = 0
      @timings.each do |timing|
      latency = (timing[0] - assumed_stream_baseline)-(timing[2]/1000.0)
      @max_latency = latency if latency > @max_latency
      @max_stream_time = timing[2] if timing[2] > @max_stream_time
    end
  end
end

def tputs(msg)
  puts Time.now.strftime('%Y-%m-%d %H:%M:%S - ') + msg.to_s
end

#####################################################
#####################################################
#####################################################

tputs "LATENCY GRAPHER STARTED"

# Clear out any environment options.
if ARGV.first == '-e'
  ARGV.shift(2)
end

@job_is_live = false
if ['-l','--live'].include? ARGV.first
  @job_is_live = true
  ARGV.shift
end

@ssh_user = nil
if ['-u','--user'].include? ARGV.first
  ARGV.shift
  @ssh_user = ARGV.shift
end

@job_id = numeric_arg_with_default(0).to_i


job = Job.find_by_id(@job_id)
raise "Job #{@job_id} not found!" unless job

tputs "GATHERING LOGS"

input_log = IngestLogs.new(get_log(job.input_media_file, 'input', 'download/download.log'))
@all_logs = {}
@all_logs["Input #{job.input_media_file.id}"] = input_log

# Use a queue to feed the threads that will parse the logs.  Tried 
# constructing as many threads as there are outputs, but for jobs with a lot 
# of outputs the number of ActiveRecord DB connections became a bottleneck 
# and caused the script to fail.
queue = Queue.new
job.output_media_files.each do |o|
  queue << o
end

# create threads to process the output logs in parallel.  Consider adjusting the number of threads (currently 2).
threads = []
2.times do  | i |
  threads << Thread.new { 
    until queue.empty?
      o = queue.pop
      @all_logs["Output #{o.id}: #{o.label}"] = WorkerLogs.new(get_log(o, 'output', 'transcode/upload.log'), get_log(o, 'output', 'transcode/latency.log'))
    end
  }
end
threads.each { |t| t.join }

tputs "DONE GATHERING LOGS"

@all_logs.keys.sort.each do |key|
  puts "Got log #{key} -- #{@all_logs[key]}"
end

@output_stream = File.open('live_job_latency_graph.html','w')
start_html_output

tputs "ANALYZING LOGS"
@all_logs.keys.sort.each do |key|
  log_info = @all_logs[key]
  if log_info.valid?
    @graph_count += 1
    @graph_names[@graph_count] = key
    log_info.analyze(key, @graph_count, @output_stream)
  end
end
tputs "DONE ANALYZING LOGS"

finish_html_output
@output_stream.close

tputs "CLEANING UP"
# Cleanup
@all_logs.values.each do |logfile|
  logfile.cleanup
end

tputs "DONE"
