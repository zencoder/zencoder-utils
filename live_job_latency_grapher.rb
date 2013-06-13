#/usr/bin/env ruby

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
end

def start_graph(title)
  @graph_count += 1
  @graph_names[@graph_count] = title
  @output_stream.puts "  function drawVisualization#{@graph_count}() {"
  @output_stream.puts "    var data = new google.visualization.DataTable();"
  @output_stream.puts "    data.addColumn('datetime', 'Time');"
  # @output_stream.puts "    data.addColumn('number', 'Average Latency');"
  # @output_stream.puts "    data.addColumn('number', 'Min Latency');"
  # @output_stream.puts "    data.addColumn('number', 'Max Latency');"
  @output_stream.puts "    data.addColumn('number', 'Latency');"
  @output_stream.puts "    data.addColumn('number', 'Percent Uploaded');"
  @output_stream.puts "    data.addColumn('number', 'Events');"
  @output_stream.puts "    data.addColumn('string', 'eventtitle');"
  @output_stream.puts "    data.addRows(["
end

def finish_graph
  @output_stream.puts "    ]);"
  @output_stream.puts
  @output_stream.puts "    var g = new Dygraph.GVizChart(document.getElementById('visualization-#{@graph_count}'));"
  @output_stream.puts "    g.draw(data, {displayAnnotations: true, labelsKMB: true, stackedGraph: false});"
  @output_stream.puts "  }"
  @output_stream.puts
  @output_stream.puts "  google.setOnLoadCallback(drawVisualization#{@graph_count});"
  @output_stream.puts
end

def finish_html_output
  @output_stream.puts '  </script>
</head>
<body style="font-family: Arial;border: 0 none;">'
  @output_stream.puts "<h2>Job #{@job_id} Live Stream Latency (#{@job_is_live ? 'Currently Streaming' : 'Finished'})</h2>"

  1.upto(@graph_count) do |i|
    @output_stream.puts "<h3>#{@graph_names[i]}</h3>"
    @output_stream.puts '<div id="visualization-' + i.to_s + '" style="width: 100%; height: 400px;"></div>'
  end

  @output_stream.puts '</body>
</html>'
end

def output_graph_data(rtmplog)
  assumed_stream_baseline = rtmplog.stream_start_time - [rtmplog.stream_start_delay, rtmplog.max_start_offset / 1000.0].max
  rtmplog.upload_timings.each do |timing|
    latency = (timing[0] - assumed_stream_baseline)-(timing[2]/1000.0)
    # percent_uploaded = (timing[2].to_f / @max_stream_time) * @max_latency
    percent_uploaded = (timing[2].to_f / rtmplog.max_stream_time) * 100.0
    # puts "TIMING: #{timing[0]} - #{timing[1]} - #{timing[2]} (#{sprintf('%0.3f', latency)})"
    @output_stream.puts "[new Date(%d), %0.3f, %0.3f, null, null]," % [(timing[0].to_f * 1000).round, latency, percent_uploaded]
  end
  
  rtmplog.events.each do |event|
    @output_stream.puts "[new Date(%d), null, null, 0, '%s']," % [(event[0].to_f * 1000).round, event[1].to_s]
  end
end

class RTMPLog
  attr_accessor :stream_start_time, :stream_start_delay, :max_start_offset, :upload_timings, :max_stream_time, :events
  
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
    @upload_timings = []
    @first_timestamp_seen = nil
    @last_timestamp_seen = nil
    @max_start_offset = 0
    @line_count = 0
    @stream_start_delay = 0
    @stream_start_time = nil


    while line = logfile.gets
      @line_count += 1
      # Ignore comments
      next if line =~ /^#/
      line_timestamp = parse_timestamp(line)
      @first_timestamp_seen ||= line_timestamp
      @last_timestamp_seen = line_timestamp

      case line
        when /WARNING: Auth failed/
          @events << [line_timestamp, :auth_failure]
        when /DEBUG: Invoking FCPublish/
          @events << [line_timestamp, :fc_publish]
        when /INFO: STREAM_START (\d+)/
          stream_start_time = $1.to_i
          @stream_start_time = line_timestamp
          @stream_start_delay = (line_timestamp - @first_timestamp_seen)
          @events << [line_timestamp, :started_streaming]
          @upload_timings << [line_timestamp, stream_start_time, 0]
        when /DEBUG: New start time offset: (\d+)/
          @max_start_offset = $1.to_i
        when /INFO: TIME (\d+) OFFSET (\d+) STREAM_TIME (\d+)/
          time,offset,stream_time = [$1.to_i, $2.to_i, $3.to_i]
          @upload_timings << [line_timestamp, time, stream_time]
        when /WARNING: WriteN, RTMP send error/
          @events << [line_timestamp, :send_error]
        when /ERROR: disconnected from remote server/
          @events << [line_timestamp, :disconnect]
        when /INFO: send_data, done sending/
          @events << [line_timestamp, :done]
      end
    end
    logfile.close

    # puts "Line count: #{@line_count}"
    # puts "First timestamp: #{@first_timestamp_seen}"
    # puts "Max start offset: #{@max_start_offset}"
    # 
    # @events.each do |event|
    #   puts "EVENT: #{event[0]} - #{event[1]}"
    # end

    assumed_stream_baseline = @stream_start_time - [@stream_start_delay, @max_start_offset / 1000.0].max

    @max_latency = 0.0
    @max_stream_time = 0
    @upload_timings.each do |timing|
      latency = (timing[0] - assumed_stream_baseline)-(timing[2]/1000.0)
      # puts "TIMING: #{timing[0]} - #{timing[1]} - #{timing[2]} (#{sprintf('%0.3f', latency)})"
      @max_latency = latency if latency > @max_latency
      @max_stream_time = timing[2] if timing[2] > @max_stream_time
    end
  
  end
end

#####################################################
#####################################################
#####################################################

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

input_log = get_log(job.input_media_file, 'input', 'download/download.log')
output_logs = job.output_media_files.map { |o| [o.label, get_log(o, 'output', 'transcode/upload.log')] }

puts "Got input log: #{input_log}"
output_logs.each do |log_info|
  puts "Got output log '#{log_info[0]}': #{log_info[1]}"
end

all_logs = [['Input', input_log]] + output_logs.sort_by { |ol| ol.first.to_s }

# def finish_graph
# def finish_html_output
# def output_graph_data(rtmplog)
# def start_graph(title)
# def start_html_output

@output_stream = File.open('live_job_latency_graph.html','w')
start_html_output

all_logs.each do |log_info|
  rtmplog = RTMPLog.new(log_info[1])
  if rtmplog.valid?
    start_graph(log_info[0])
    output_graph_data(rtmplog)
    finish_graph
  end
end

finish_html_output
@output_stream.close

# Cleanup
File.unlink(input_log)
output_logs.each do |log_info|
  File.unlink(log_info[1]) if log_info[1]
end



# // var annotatedtimeline = new google.visualization.AnnotatedTimeLine(document.getElementById('visualization'));
# // annotatedtimeline.draw(data, {'displayAnnotations': true});
# 
# var g = new Dygraph.GVizChart(document.getElementById("visualization"));
# g.draw(data, {displayAnnotations: true, labelsKMB: true, stackedGraph: true});

