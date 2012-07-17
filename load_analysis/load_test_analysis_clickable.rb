#!/usr/bin/env ruby


input_lines = []
ARGV.each do |f|
  puts "Reading #{f}..."
  input_lines += File.readlines(f)
end

if ARGV.length == 1 && ARGV.first =~ /\.txt/
  @output_filename = $` + '.html'
else
  @output_filename = 'load_test_analysis_output.html'
end
puts "OUTPUT FILENAME: #{@output_filename}"

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

max_cpu = 1600
max_memory = 1600
max_time = @runs.collect { |r| r[:max_time] }.max

puts "#{@runs.count} test runs found..."
puts "Max Time: %0.2f" % max_time
puts


f = File.open(@output_filename, 'w')
f.puts <<END_HTML
<html>
  <head>
    <script type="text/javascript" src="https://www.google.com/jsapi"></script>
    <script type="text/javascript">
      google.load("visualization", "1", {packages:["corechart"]});
      var charts = [];
    </script>
    <script type="text/javascript">

END_HTML


@setting_values = {}

@runs.each do |test_run|
  f.puts "var data = new google.visualization.DataTable();"
  f.puts "data.addColumn('number','Time');"
  f.puts "data.addColumn('number','CPU');"
  f.puts "data.addColumn('number','Mem');"

  test_run[:stats].each do |stat|
    f.puts "data.addRow([%0.2f, %0.1f, null]);" % [stat[:time], stat[:cpu]]
  end
  test_run[:stats].each do |stat|
    f.puts "data.addRow([%0.2f, null, %0.1f]);" % [stat[:time], stat[:mem]]
  end

  max_time_for_chart = (test_run[:stats].map { |s| s[:time] }.max / 100.0).ceil * 100
  f.puts "var draw_options = { width: 800, height: 400, lineWidth: 2, pointSize: 0, vAxis: { maxValue: 1600, minValue: 0 }, hAxis: { minValue: 0, maxValue: #{max_time_for_chart} } };"
  f.puts "var command = '#{test_run[:command].strip}';"

  f.puts "var settings = {"
  test_run[:settings].each_pair do |k,v|
    f.puts "  #{k}: '#{v}',"
    @setting_values[k] ||= {}
    @setting_values[k][v] = true
  end
  f.puts "}"

  f.puts "charts.push({ data: data, draw_options: draw_options, command: command, settings: settings });"
  f.puts
end


@settings_with_multiple_values = []
@setting_values.each_pair { |k,v| @settings_with_multiple_values << k if v.size > 1 }

f.puts <<END_HTML

function update() {
  var chart_set = [];

  var clickable_settings = [#{@settings_with_multiple_values.map { |s| "'#{s}'" }.join(',')}];
  var chosen_settings = {};

  var all_inputs = document.getElementsByTagName('INPUT');
  for (i in all_inputs) {
    var input = all_inputs[i];
    if (input.checked) {
      if (!chosen_settings[input.name]) {
        chosen_settings[input.name] = [];
      }
      chosen_settings[input.name].push(input.value);
    }
  }
  
  for (c in charts) {
    var chart = charts[c];
    var include = true;
    for (i in clickable_settings) {
      var setting = clickable_settings[i];
      var valid_values = chosen_settings[setting];
      if (!valid_values) {
        document.getElementById('error-box').innerHTML = "choose a(n) " + setting;
        return;
      }
      
      var matches = false;
      for (j in valid_values) {
        if (valid_values[j] == chart.settings[setting]) matches = true;
      }
      
      if (!matches) {
        include = false;
      }
    }
    
    if (include) {
      chart_set.push(chart);
    }
  }

  if (chart_set.length > 20) {
    document.getElementById('error-box').innerHTML = 'Too many matching charts.';
  } else if (chart_set.length > 0) {
    var chart_container = document.getElementById('chart-container');
    chart_container.innerHTML = '';
    document.getElementById('error-box').innerHTML = '';
    
    for (c in chart_set) {
      var chart = chart_set[c];
      var title = document.createElement('DIV');
      chart_container.appendChild(title);
      title.innerHTML = chart.command + "<br>" + "Concurrency: " + chart.settings.concurrency;
      var chart_box = document.createElement('DIV');
      chart_container.appendChild(chart_box);
      var chart_obj = new google.visualization.ScatterChart(chart_box);
      chart_obj.draw(chart.data, chart.draw_options);
    }
    
  } else {
    document.getElementById('error-box').innerHTML = 'No charts match selection.';
  }
}
    </script>
  </head>
  <body>
  
  <div id="options-form" style="position:absolute; width: 190px; margin:0; padding: 5px; border: 1px dashed #ccc">
    <div>
END_HTML

@setting_values.keys.sort_by { |k| k.to_s }.each do |setting_name|
  setting_values_hash = @setting_values[setting_name]
  f.puts "<b>#{setting_name}:</b><br>"
  if setting_values_hash.size > 1
    setting_values_hash.keys.sort.each do |v|
      f.puts "&nbsp;&nbsp;&nbsp;&nbsp;<input type=\"checkbox\" name=\"#{setting_name}\" value=\"#{v}\" onclick=\"update()\">#{v}<br>"
    end
  else
    f.puts "&nbsp;&nbsp;&nbsp;&nbsp;#{setting_values_hash.keys.first}<br>"
  end
  f.puts "<br>"
end

f.puts <<END_HTML
    <div id="error-box" style="color:red; font-weight: bold"></div>
    </div>
  </div>

  <div id="chart-container" style="position:absolute; left: 220px; padding: 5px; margin-right: 10px; border: 1px dashed #ccc">
  </div>
  
  </body>
</html>
END_HTML

f.close


