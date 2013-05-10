#!/usr/bin/env ruby
require 'time'

class NormalizedHistogram
  attr_reader :min_y, :max_y, :avg_buckets, :min_buckets, :max_buckets, :bucket_count

  def initialize(min_x, max_x, bucket_count)
    raise "Invalid min/max dimensions!" if max_x <= min_x
    raise "Invalid bucket_count!" if bucket_count.to_f.round < 1
    @min_x = min_x
    @max_x = max_x
    @x_range = (@max_x - @min_x).to_f
    @bucket_count = bucket_count.to_f.round
    @min_y = nil
    @max_y = nil
    @buckets = []

    @avg_buckets = []
    @min_buckets = []
    @max_buckets = []
    
    @normalized = false
  end

  def add(x, y)
    return nil if x < @min_x
    return nil if x > @max_x
    @min_y = y if @min_y.nil? || y < @min_y
    @max_y = y if @max_y.nil? || y > @max_y

    bucket_number = bucket_for(x)
    @buckets[bucket_number] ||= []
    @buckets[bucket_number] << y 
    @normalized = false

    true
  end

  def bucket_for(x)
    [(((x - @min_x) / @x_range) * @bucket_count).to_i, @bucket_count - 1].min
  end

  def dump
    normalize unless @normalized
    @bucket_count.times do |i|
      # puts "%03d: %6.3f - %6.3f - %6.3f" % [i, @min_buckets[i], @avg_buckets[i], @max_buckets[i]]
      puts "%6.3f - %6.3f - %6.3f" % [@min_buckets[i], @avg_buckets[i], @max_buckets[i]]
    end
  end

  def normalize
    @avg_buckets = []
    @min_buckets = []
    @max_buckets = []

    # First loop - calculate only for buckets with values.
    @bucket_count.times do |bucket_number|
      if @buckets[bucket_number]
        values = @buckets[bucket_number]
        @avg_buckets[bucket_number] = mean(values)
        @min_buckets[bucket_number] = values.min
        @max_buckets[bucket_number] = values.max
      end
    end

    # Second loop - interpolate missing values.
    prev_values = nil
    @bucket_count.times do |bucket_number|
      # Skip if we already did this one.
      next if @avg_buckets[bucket_number]

      if @buckets[bucket_number]
        prev_values = { :avg => @avg_buckets[bucket_number], :max => @max_buckets[bucket_number], :min => @min_buckets[bucket_number] }
        next
      end

      # Find next bucket with values
      next_values = nil
      next_bucket_number = nil
      bucket_number.upto(@bucket_count - 1) do |i|
        next unless @avg_buckets[i]
        next_values = { :avg => @avg_buckets[i], :max => @max_buckets[i], :min => @min_buckets[i] }
        next_bucket_number = i
        break
      end

      raise "Normalizing on empty set!" if prev_values.nil? && next_values.nil?

      # Handle edge "extrapolation" by copying.
      if prev_values.nil?
        bucket_number.upto(next_bucket_number - 1) do |i|
          @avg_buckets[i] = next_values[:avg]
          @min_buckets[i] = next_values[:min]
          @max_buckets[i] = next_values[:max]
        end
        next
      elsif next_values.nil?
        bucket_number.upto(@bucket_count - 1) do |i|
          @avg_buckets[i] = prev_values[:avg]
          @min_buckets[i] = prev_values[:min]
          @max_buckets[i] = prev_values[:max]
        end
        next
      end

      spots_to_interpolate = (next_bucket_number - bucket_number)
      spots_to_interpolate.times do |i|
        cur_bucket = bucket_number + i
        fraction = (i + 1).to_f / (spots_to_interpolate + 1)
        @avg_buckets[cur_bucket] = prev_values[:avg] + ((next_values[:avg] - prev_values[:avg]) * fraction)
        @min_buckets[cur_bucket] = prev_values[:min] + ((next_values[:min] - prev_values[:min]) * fraction)
        @max_buckets[cur_bucket] = prev_values[:max] + ((next_values[:max] - prev_values[:max]) * fraction)
      end

      prev_values = { :avg => @avg_buckets[bucket_number], :max => @max_buckets[bucket_number], :min => @min_buckets[bucket_number] }
    end

    @normalized = true
  end

  private

  def mean(values)
    (values.inject(0.0) { |s,v| s + v }) / values.length
  end
end


def parse_timestamp(line)
  if line =~ /\[(\d+-\d+-\d+ \d+:\d+:\d+\.\d+)\]/
    Time.parse($1 + ' -0000')
  end
end


logfile_name = ARGV.first
logfile = File.open(logfile_name, 'r')


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

hist = NormalizedHistogram.new(@first_timestamp_seen.to_f, @last_timestamp_seen.to_f, 1000)
assumed_stream_baseline = @stream_start_time - [@stream_start_delay, @max_start_offset / 1000.0].max

@max_latency = 0.0
@max_stream_time = 0
@upload_timings.each do |timing|
  latency = (timing[0] - assumed_stream_baseline)-(timing[2]/1000.0)
  # puts "TIMING: #{timing[0]} - #{timing[1]} - #{timing[2]} (#{sprintf('%0.3f', latency)})"
  hist.add(timing[0].to_f, latency)
  @max_latency = latency if latency > @max_latency
  @max_stream_time = timing[2] if timing[2] > @max_stream_time
end


# var d = new Date();
# var d = new Date(milliseconds);
# var d = new Date(dateString);
# var d = new Date(year, month, day, hours, minutes, seconds, milliseconds);


puts <<__EOH__
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta http-equiv="content-type" content="text/html; charset=utf-8" />
  <script type="text/javascript" src="http://www.google.com/jsapi"></script>
  <script type="text/javascript">
__EOH__

puts "  google.load('visualization', '1', {packages: ['annotatedtimeline']});"
puts "  function drawVisualization() {"
puts "    var data = new google.visualization.DataTable();"
puts "    data.addColumn('datetime', 'Time');"
# puts "    data.addColumn('number', 'Average Latency');"
# puts "    data.addColumn('number', 'Min Latency');"
# puts "    data.addColumn('number', 'Max Latency');"
puts "    data.addColumn('number', 'Latency');"
puts "    data.addColumn('number', 'Percent Uploaded');"
puts "    data.addColumn('number', 'Events');"
puts "    data.addColumn('string', 'eventtitle');"
puts "    data.addRows(["

# hist.normalize
# hist.bucket_count.times do |bn|
#   puts "[new Date(%d), %0.3f, %0.3f, %0.3f, null]," % [hist.
# end

assumed_stream_baseline = @stream_start_time - [@stream_start_delay, @max_start_offset / 1000.0].max
@upload_timings.each do |timing|
  latency = (timing[0] - assumed_stream_baseline)-(timing[2]/1000.0)
  # percent_uploaded = (timing[2].to_f / @max_stream_time) * @max_latency
  percent_uploaded = (timing[2].to_f / @max_stream_time) * 100.0
  # puts "TIMING: #{timing[0]} - #{timing[1]} - #{timing[2]} (#{sprintf('%0.3f', latency)})"
  puts "[new Date(%d), %0.3f, %0.3f, null, null]," % [(timing[0].to_f * 1000).round, latency, percent_uploaded]
end

@events.each do |event|
  puts "[new Date(%d), null, null, 0, '%s']," % [(event[0].to_f * 1000).round, event[1].to_s]
end

puts "    ]);"
puts "  "
puts "    var annotatedtimeline = new google.visualization.AnnotatedTimeLine("
puts "        document.getElementById('visualization'));"
puts "    annotatedtimeline.draw(data, {'displayAnnotations': true});"
puts "  }"
puts "  "
puts "  google.setOnLoadCallback(drawVisualization);"

puts <<__EOH__
  </script>
</head>
<body style="font-family: Arial;border: 0 none;">
<div id="visualization" style="width: 100%; height: 400px;"></div>
</body>
</html>
__EOH__
