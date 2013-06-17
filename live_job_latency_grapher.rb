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
  @output_stream.puts "  var g;"
  @output_stream.puts "  var rtmp_data_set = new Array();"
  @output_stream.puts "  var event_data_set = new Array();"
  @output_stream.puts
  @output_stream.puts "  function drawVisualization() {"
end

# Output a data set for 
def output_graph_data(title,rtmplog)
  @graph_count += 1
  @graph_names[@graph_count] = title
  case @graph_count
  when 1
    @output_stream.puts "    // Input dataset"
    series_name = "Input Latency"
  else
    @output_stream.puts "    // Output dataset: #{title}"
    series_name = "Output Latency"
  end

  
  # EVENT DATA
  event_timestamp_hash = Hash.new
  @output_stream.puts "    event_data_set[#{@graph_count}] = ["
  rtmplog.events.each do |event|
    # add entry to the timestamp map for lookup when processing the RTMP logs
    event_timestamp_hash[Time.at(event[0].to_f.round)] = "default"

    @output_stream.puts "{"
    @output_stream.puts "series: \"#{series_name}\","
    @output_stream.puts "x: \"%s\"," % Time.at(event[0].to_f.round).strftime("%F %TZ")
    @output_stream.puts "shortText: \"#{event[1].to_s}\","
    @output_stream.puts "text: \"#{event[1].to_s}\","
    @output_stream.puts "},"
  end
  @output_stream.puts "    ];"
  @output_stream.puts

  # RTMP DATA
  @output_stream.puts "    var rtmp_data_#{@graph_count} = new google.visualization.DataTable();"
  @output_stream.puts "    rtmp_data_#{@graph_count}.addColumn('datetime', 'Time');"
  @output_stream.puts "    rtmp_data_#{@graph_count}.addColumn('number', '#{series_name}');"
  @output_stream.puts "    rtmp_data_#{@graph_count}.addRows(["

  assumed_stream_baseline = rtmplog.stream_start_time - [rtmplog.stream_start_delay, rtmplog.max_start_offset / 1000.0].max
  rtmplog.upload_timings.each do |timing|
    latency = (timing[0] - assumed_stream_baseline)-(timing[2]/1000.0)
    # puts "TIMING: #{timing[0]} - #{timing[1]} - #{timing[2]} (#{sprintf('%0.3f', latency)})"
    # case timing[3]
    # when nil
      # @output_stream.puts "[new Date(%d), %0.3f, undefined]," % [(timing[0].to_f * 1000).round, latency]
    # else
    #   @output_stream.puts "[new Date(%d), %0.3f, \"%s\"]," % [(timing[0].to_f * 1000).round, latency, timing[3]]
    # end


     @output_stream.puts "[new Date(%d), %0.3f]," % [(timing[0].to_f * 1000).round, (latency < 0.0 ? 0 : latency)]

     if event_timestamp_hash[Time.at(timing[0].to_f.round)] == "default" then
       @output_stream.puts "[new Date(%d), %0.3f]," % [timing[0].to_f.round * 1000, (latency < 0.0 ? 0 : latency)]
       event_timestamp_hash[Time.at(timing[0].to_f.round)] = "complete"
     end

  end
  @output_stream.puts "    ]);"
  @output_stream.puts "    rtmp_data_set[#{@graph_count}] = rtmp_data_#{@graph_count};"
end

def finish_html_output

  @output_stream.puts
  @output_stream.puts "    g = new Dygraph(document.getElementById(\"visualization\"));"
  # @output_stream.puts "    g = new google.visualization.AnnotatedTimeLine(document.getElementById(\"visualization\"));"
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
        var merged_data = google.visualization.data.join(rtmp_data_set[1], rtmp_data_set[i], 'full', [[0,0]], [1], [1]);
        g.updateOptions({ 'file': merged_data, connectSeparatedPoints: true, legend: 'always', axisLabelFontSize: 12, displayAnnotations: true, showRangeSelector: true, valueRange: [0,null] } );
        g.setAnnotations(event_data_set[1].concat(event_data_set[i]));
      }
      </script>"
  @output_stream.puts '</body>
</html>'
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
    @last_stream_time = 0


    while line = logfile.gets
      @line_count += 1
      # Ignore comments
      next if line =~ /^#/
      line_timestamp = parse_timestamp(line)
      @first_timestamp_seen ||= line_timestamp
      @last_timestamp_seen = line_timestamp

      case line
        when /WARNING: Auth failed/
          @events << [line_timestamp, time, stream_time]
          @upload_timings << [line_timestamp, stream_start_time, @last_stream_time, nil]
        when /DEBUG: Invoking FCPublish/
          @events << [line_timestamp, :fc_publish]
          @upload_timings << [line_timestamp, stream_start_time, @last_stream_time, nil]

        when /INFO: STREAM_START (\d+)/
          stream_start_time = $1.to_i
          @last_stream_time = 0
          @stream_start_time = line_timestamp
          @stream_start_delay = (line_timestamp - @first_timestamp_seen)
          @events << [line_timestamp, :started_streaming]
          @upload_timings << [line_timestamp, stream_start_time, 0, nil]
          @last_time = line_timestamp
        when /DEBUG: New start time offset: (\d+)/
          @max_start_offset = $1.to_i
        when /INFO: TIME (\d+) OFFSET (\d+) STREAM_TIME (\d+)/
          time,offset,stream_time = [$1.to_i, $2.to_i, $3.to_i]
          @upload_timings << [line_timestamp, time, stream_time, nil]
          @last_time = time
          @last_stream_time = stream_time
        when /WARNING: WriteN, RTMP send error/
          @events << [line_timestamp, :send_error]
          @upload_timings << [line_timestamp, stream_start_time, @last_stream_time, nil]
        when /ERROR: disconnected from remote server/
          @events << [line_timestamp, :disconnect]
          @upload_timings << [line_timestamp, stream_start_time, @last_stream_time, nil]
        when /INFO: send_data, done sending/
          @events << [line_timestamp, :done]
          @upload_timings << [line_timestamp, stream_start_time, @last_stream_time, nil]

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

# locate the input log file within the context of the job input directory
input_log = get_log(job.input_media_file, 'input', 'download/download.log')

# for each of the transcoding outputs, locate the upload log file within the context of the job output directory
# the upload log contains the rmtppush logging output showing info about the upload activity
# from zencoder to the CDN/publish point.
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

# parse the input stream RTMP log
all_logs.each do |log_info|
  rtmplog = RTMPLog.new(log_info[1])
  if rtmplog.valid?
    output_graph_data(log_info[0],rtmplog)
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

