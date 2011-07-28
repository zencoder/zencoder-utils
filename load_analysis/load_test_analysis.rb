#!/usr/bin/env ruby


input_lines = []
ARGV.each do |f|
  puts "Reading #{f}..."
  input_lines += File.readlines(f)
end

puts
puts "#{input_lines.length} lines to analyze..."


@baselines = Hash.new { |h,k| h[k] = [] }
@runs = []


line_count = 0
current_item = nil

input_lines.each do |line|
  line_count += 1
  case line
  when /^\*BASELINE_START/
    if current_item
      puts "UNFINISHED ITEM AT LINE #{line_count}"
    end
    current_item = {}
  when /^\*CODEC: (\S+)/
    current_item[:codec] = $1
  when /^\*TIME: (\S+)/
    current_item[:time] = $1.to_f
  when /^\*BASELINE_END/
    @baselines[current_item[:codec]] << current_item[:time]
    current_item = nil

  when /^\*RESULT_START/
    if current_item
      puts "UNFINISHED ITEM AT LINE #{line_count}"
    end
    current_item = { :stats => [] }
  when /^\*SETTINGS: /
    current_item[:settings] = eval($')
  when /^\*COMMAND: /
    current_item[:command] = $'
  when /^\*MAX_CPU: (\S+)/
    current_item[:max_cpu] = $1.to_f
  when /^\*MAX_MEM: (\S+)/
    current_item[:max_mem] = $1.to_f
  when /^\*MAX_PROCS: (\S+)/
    current_item[:max_procs] = $1.to_i
  when /^\*MAX_THREADS: (\S+)/
    current_item[:max_threads] = $1.to_i
  when /^\*RESULT_END/
    current_item[:max_time] = current_item[:stats].map { |s| s[:time] }.max
    @runs << current_item
    current_item = nil
  when /^\{/
    if current_item
      stats = eval(line)
      if stats[:cpu] # Sometimes we get ones with just :time
        current_item[:stats] << stats
      end
    end
  else
    puts "Unknown info at line #{line_count}"
  end
end
puts

@baselines.keys.each do |codec|
  @baselines[codec] = @baselines[codec].inject(0.0) { |s,v| s + v } / @baselines[codec].length
  puts "Baseline for #{codec}: %0.2f" % @baselines[codec]
end
puts

######################################

max_cpu = 800
max_memory = 800
max_time = @runs.collect { |r| r[:max_time] }.max

puts "#{@runs.count} test runs found..."
puts "Max Time: %0.2f" % max_time
puts


f = File.open('load_test_analysis_output.html', 'w')
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

test_run_count = 0
@runs.each do |test_run|
  test_run_count += 1

  f.puts "<h4>#{test_run[:command]}</h4>"
  if test_run[:settings][:concurrency].to_i > 1
    f.puts "<h3>CONCURRENCY: #{test_run[:settings][:concurrency].to_i}</h3>"
  end
  f.puts "<div id=\"test_run_#{test_run_count}\"></div>"
  f.puts "<script type=\"text/javascript\">"
  f.puts "var data_#{test_run_count} = new google.visualization.DataTable();"
  f.puts "data_#{test_run_count}.addColumn('string','Time')"
  f.puts "data_#{test_run_count}.addColumn('number','CPU')"
  f.puts "data_#{test_run_count}.addColumn('number','Mem')"
  f.puts "data_#{test_run_count}.addRows(["

  # METHOD A
  # test_run[:stats].each do |stat|
  #   f.puts "  ['%0.2f', %0.1f, %0.1f]," % [stat[:time], stat[:cpu], stat[:mem]]
  # end
  
  # METHOD B
  data_point_count = max_time.ceil + 1
  data_points = []
  max_point = 0
  test_run[:stats].each do |stat|
    point = stat[:time].round
    max_point = [point, max_point].max
    data_points[point] = stat
  end
  prev_cpu = 0.0
  prev_mem = 0.0
  data_point_count.times do |t|
    p = data_points[t] #|| { :cpu => prev_cpu, :mem => prev_mem }
    if t > max_point
      p ||= { :cpu => 0.0, :mem => 0.0 }
    else
      p ||= { :cpu => prev_cpu, :mem => prev_mem }
    end
    f.puts "  ['%d', %0.1f, %0.1f]," % [t, p[:cpu], p[:mem]]
    prev_cpu = p[:cpu]
    prev_mem = p[:mem]
  end


  f.puts "]);"
  f.puts "var chart_#{test_run_count} = new google.visualization.AreaChart(document.getElementById('test_run_#{test_run_count}'));"
  f.puts "chart_#{test_run_count}.draw(data_#{test_run_count}, { width: 800, height: 400, vAxis: { maxValue: #{max_cpu}, minValue: 0 } });"
  f.puts "</script>"
end

f.puts <<END_HTML
  </body>
</html>
END_HTML

f.close




