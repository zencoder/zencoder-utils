#!/usr/bin/env ruby

$: << File.dirname(__FILE__)
require 'settings_grid'

# To account for:
#   Download, Video Transcode, Audio Transcode, Thumbnail, Upload
#   Transcodes: Setup vs. duration-based
# 
# VIDEO TESTS
# -----------
# Encoding: 640x480, 1280x720, 1920x1080
# Scaling: as-is, up, down
# Concurrency: 1, 2, 3
# Speed: 1, 3, 5
# Quality: 1, 3, 5
# Watermarking: with, without
# Codecs: H264, VP8, VP6, WMV
# 
# AUDIO TESTS
# -----------
# Codecs: Nero, MP3, WMV
# Resampling: Basic, Sample Rate, Channels
# Quality: 1, 3, 5
# Effects: Normalize, High-pass, Normalize & High-pass
# 


class StatCollector
  SAMPLING_COMMAND = 'COLUMNS=512 top -b -n 1 -c -H | grep -i -E "x264|ffmpeg|mp4box|faac|zenengine|nero|flix|mplayer|mencoder"'

  mem_info = `top -b -n 1 | grep 'Mem:'`
  if mem_info =~ /Mem: *(\d+)k +total/
    TOTAL_MEM = $1.to_f / 1024 # In megabytes
  else
    TOTAL_MEM = 8192.0 # 8 gigs in megabytes as default
  end

  def initialize(ignore_flix = true, extra_data = {})
    @sample_sets = []
    @ignore_flix = ignore_flix
    @extra_data = extra_data
    @start_time = Time.now
  end
  
  def collect
    stats = Hash.new(0.0)
    stats.merge(@extra_data)
    unique_processes = {}
    results = `#{SAMPLING_COMMAND}`.split(/\n/)
    stats[:time] = Time.now - @start_time

    results.each do |line|
      # PID USER      PR  NI  VIRT  RES  SHR S %CPU %MEM    TIME+  COMMAND
      pid,user,priority,nice,virt,res,shr,state,cpu,mem,time,command = line.split(' ',12)

      next if command =~ /grep|java -cp|^sh /
      next if command =~ /flix/ && (cpu.to_f == 0.0 || @ignore_flix)

      # Bad reporting from hypervisors sometimes.
      cpu = '100.0' if cpu.to_f > 999
      
      # STDOUT.puts "CPU=%3.1f, MEM=%6d: #{command}" % [cpu,mem]

      stats[:cpu] += cpu.to_f
      stats[:threads] += 1
      if !unique_processes[command]
        stats[:mem] += mem.to_f * TOTAL_MEM / 100.0
        stats[:procs] += 1
      end

      unique_processes[command] = true
    end
    
    @sample_sets << stats
  end

  def display
    @sample_sets.each do |stats|
      puts "TIME=%06.2f CPU=%05.1f MEM=%06.1f PROCS=%03d THREADS=%03d" % [stats[:time], stats[:cpu], stats[:mem], stats[:procs], stats[:threads]]
    end
  end
  
  def save(filename, meta_values = {})
    File.open(filename, 'a') do |f|
      f.puts "RESULT_START"
      f.puts "META=#{meta_values.inspect}"
      @sample_sets.each do |stats|
        f.puts "STATS=#{stats.inspect}"
      end
      f.puts "RESULT_END"
    end
  end
end


$worker_type = `curl -f -s http://169.254.169.254/latest/meta-data/instance-type`.strip


@set = nil
mode = ARGV.shift
case mode
when '-1'
  @set = 1
when '-2'
  @set = 2
when '-3'
  @set = 3
when '-4'
  @set = 4
when '-5'
  @set = 5
when '-6'
  @set = 6
when '-7'
  @set = 7
when '-a'
  @set = :audio
when '-v'
  @set = :video
when '-c1'
  @set = :combined_1
when '-c2'
  @set = :combined_2
else
  puts "Please choose a set of tests!"
  exit
end

@save_file_name = "load_test_results_#{@set.to_s}.txt"
puts "SAVE FILE NAME: #{@save_file_name}"


video_tests = ZenEngine::SettingsGrid.new([:kind, :decoder, :input_rate, :output_rate, :input_width, :output_width, :concurrency, :speed, :quality, :watermark, :codec, :postprocess])

if @set == 1 || @set == :video || @set == :baselines
  video_tests << { :kind => 'tina', :input_rate => 29.97, :output_rate => 29.97, :decoder => 'ffmpeg', :input_width => [640,1280,1920], :output_width => [640,1280,1920], :concurrency => 1, :speed => 3, :quality => 3, :watermark => 0, :codec => ["h264", "vp8", "vp6", "wmv"], :postprocess => 'none' }
  video_tests << { :kind => 'tina', :input_rate => 29.97, :output_rate => 29.97, :decoder => 'ffmpeg', :input_width => 1280, :output_width => [640,1280,1920], :concurrency => [2,3], :speed => 3, :quality => 3, :watermark => 0, :codec => ["h264", "vp8", "vp6", "wmv"], :postprocess => 'none' }
end

if @set == 2 || @set == :video
  video_tests << { :kind => 'tina', :input_rate => 29.97, :output_rate => 29.97, :decoder => 'ffmpeg', :input_width => 1280, :output_width => 1280, :concurrency => 1, :speed => [1,2,3,4,5], :quality => [1,2,3,4,5], :watermark => 0, :codec => ["h264", "vp8", "vp6", "wmv"], :postprocess => 'none' }
  video_tests << { :kind => 'tina', :input_rate => 29.97, :output_rate => 29.97, :decoder => 'ffmpeg', :input_width => 1280, :output_width => [640,1280,1920], :concurrency => 1, :speed => 3, :quality => 3, :watermark => 1, :codec => "h264", :postprocess => 'none' }
end

if @set == 3 || @set == :video
  video_tests << { :kind => ['tina', 'bbb', 'earth', 'static'], :input_rate => 29.97, :output_rate => 29.97, :decoder => 'ffmpeg', :input_width => 1280, :output_width => 1280, :concurrency => 1, :speed => 3, :quality => 3, :watermark => 0, :codec => ["h264", "vp8", "vp6", "wmv"], :postprocess => 'none' }
  video_tests << { :kind => 'tina', :input_rate => 29.97, :output_rate => 29.97, :decoder => ['ffmpeg', 'mplayer'], :input_width => 1280, :output_width => [640,1280,1920], :concurrency => 1, :speed => 3, :quality => 3, :watermark => 0, :codec => "h264", :postprocess => 'none' }
end

if @set == 4 || @set == :video
  video_tests << { :kind => 'tina', :input_rate => 29.97, :output_rate => 29.97, :decoder => ['ffmpeg', 'mplayer'], :input_width => 1280, :output_width => 1280, :concurrency => 1, :speed => 3, :quality => 3, :watermark => [0,1], :codec => "h264", :postprocess => ['none','autolevel','sharpen','autolevel_sharpen'] }
  video_tests << { :kind => 'tina', :input_rate => [15, 29.97, 59.94], :output_rate => [15, 29.97, 59.94], :decoder => 'ffmpeg', :input_width => 1280, :output_width => 1280, :concurrency => 1, :speed => 3, :quality => 3, :watermark => 0, :codec => "h264", :postprocess => 'none' }
end

if @set == 5 || @set == :video
  video_tests << { :kind => 'tina', :input_rate => 29.97, :output_rate => 29.97, :decoder => 'ffmpeg', :input_width => [640,1280], :output_width => [640,800,960,1280], :concurrency => [1,2,3,4], :speed => 3, :quality => 3, :watermark => 0, :codec => "h264", :postprocess => 'none' }
end

if @set == 6 || @set == :video
  video_tests << { :kind => 'tina', :input_rate => 29.97, :output_rate => 29.97, :decoder => 'ffmpeg', :input_width => 640, :output_width => [640,800,960,1280], :concurrency => [1,2,3,4,5,6], :speed => 3, :quality => 3, :watermark => 0, :codec => "h264", :postprocess => 'none' }
end
if @set == 7 || @set == :video
  video_tests << { :kind => 'tina', :input_rate => 29.97, :output_rate => 29.97, :decoder => 'ffmpeg', :input_width => 1280, :output_width => [640,800,960,1280], :concurrency => [1,2,3,4,5,6], :speed => 3, :quality => 3, :watermark => 0, :codec => "h264", :postprocess => 'none' }
end


audio_tests = ZenEngine::SettingsGrid.new([:input_rate, :output_rate, :input_channels, :output_channels, :quality, :effects, :codec])

if @set == :audio
  audio_tests << { :input_rate => [22050, 44100, 48000], :output_rate => [22050, 44100, 48000], :input_channels => [1,2], :output_channels => [1,2], :quality => 3, :effects => "none", :codec => ["aac", "mp3", "wma"] }
  audio_tests << { :input_rate => 44100, :output_rate => 44100, :input_channels => 2, :output_channels => 2, :quality => [1,2,3,4,5], :effects => "none", :codec => ["aac", "mp3", "wma"] }
  audio_tests << { :input_rate => 44100, :output_rate => 44100, :input_channels => 2, :output_channels => 2, :quality => 3, :effects => ["none", "normalize", "highpass", "normalize_highpass"], :codec => "aac" }
end

combined_tests = ZenEngine::SettingsGrid.new([:input_width, :output_width, :codec, :concurrency])

if @set == :combined_1
  combined_tests << { :input_width => [640,1280], :output_width => [640,1280,1920], :concurrency => [1,2,3,4,5,6], :codec => "h264" }
end
if @set == :combined_2
  combined_tests << { :input_width => [640,1280], :output_width => [640,1280,1920], :concurrency => [1,4,6,8,12], :codec => "vp6" }
end


puts "VIDEO TESTS"
video_tests.settings_dump
puts

puts "AUDIO TESTS"
audio_tests.settings_dump
puts

puts "COMBINED TESTS"
combined_tests.settings_dump
puts

puts
puts

# Get codec baseline times...
@codec_baselines = {}
video_tests.options_for(:codec).each do |codec|
  puts "Running baseline for video codec #{codec}..."
  command = "zenengine /tmp/tina_1280_2997.mp4 --skip-audio --video-codec #{codec} --clip-length 1"
  start_time = Time.now
  `#{command}`
  `#{command}`
  end_time = Time.now
  @codec_baselines[codec] = (end_time - start_time) / 2.0
  puts "Done!  (%0.2f)" % @codec_baselines[codec]
end
audio_tests.options_for(:codec).each do |codec|
  puts "Running baseline for audio codec #{codec}..."
  command = "zenengine /tmp/audio_44100_2.mp4 --skip-video --audio-codec #{codec} --beta-aac-encoder --clip-length 1"
  start_time = Time.now
  `#{command}`
  `#{command}`
  end_time = Time.now
  @codec_baselines[codec] = (end_time - start_time) / 2.0
  puts "Done!  (%0.2f)" % @codec_baselines[codec]
end
combined_tests.options_for(:codec).each do |codec|
  codec_name = codec.to_s + '/aac'
  puts "Running baseline for combined codec #{codec_name}..."
  command = "zenengine /tmp/combined_1280_2997_600s.mp4 --audio-codec aac --beta-aac-encoder --video-codec #{codec} --clip-length 1"
  start_time = Time.now
  `#{command}`
  `#{command}`
  end_time = Time.now
  @codec_baselines[codec_name] = (end_time - start_time) / 2.0
  puts "Done!  (%0.2f)" % @codec_baselines[codec_name]
end

puts
puts

total_test_count = video_tests.settings_grid.length + audio_tests.settings_grid.length + combined_tests.settings_grid.length
current_test_number = 0

video_tests.settings_grid.each do |s|
  current_test_number += 1
  
  rate_suffix = s[:input_rate].to_s.gsub('.','')
  command = "zenengine /tmp/#{s[:kind]}_#{s[:input_width]}_#{rate_suffix}.mp4 --skip-audio --video-codec #{s[:codec]} --upscale --width #{s[:output_width]} "
  command << "--speed #{s[:speed]} --quality #{s[:quality]} --frame-rate #{s[:output_rate]} "
  command << "--use-mplayer-for-video " if s[:decoder] == 'mplayer'
  command << "--watermark-file /tmp/watermark.png " if s[:watermark] == 1
  command << "--autolevel " if s[:postprocess] =~ /autolevel/
  command << "--sharpen " if s[:postprocess] =~ /sharpen/
  
  puts "Test #{current_test_number}/#{total_test_count}"
  puts "Running '#{command}' with concurrency of #{s[:concurrency]}..."
  
  if s[:codec] == 'vp6'
    ignore_flix = false
  else
    ignore_flix = true
  end
  
  encode_threads = []
  start_time = Time.now
  stat_collector = StatCollector.new(ignore_flix)

  s[:concurrency].times do
    encode_threads << Thread.new do
      `#{command}`
    end
  end
  
  while encode_threads.length > 0
    iteration_start_time = Time.now

    stat_collector.collect

    encode_threads.each do |t|
      if !t.alive?
        t.join
        encode_threads.delete(t)
      end
    end
    
    STDOUT.print '.'
    STDOUT.flush

    sleep (1 - (Time.now - iteration_start_time) - 0.01)
  end
  
  end_time = Time.now

  puts
  puts "Done! (%0.2f)" % (end_time-start_time)

  puts
  stat_collector.display
  puts
  
  stat_collector.save(@save_file_name, :worker_type => $worker_type, :concurrency => s[:concurrency], :command => command, :baseline => @codec_baselines[s[:codec]])
end


audio_tests.settings_grid.each do |s|
  current_test_number += 1

  command = "zenengine /tmp/audio_#{s[:input_rate]}_#{s[:input_channels]}.mp4 --skip-video --audio-codec #{s[:codec]} --beta-aac-encoder "
  command << "--audio-sample-rate #{s[:output_rate]} --audio-channels #{s[:output_channels]} --audio-quality #{s[:quality]} "
  command << "--audio-normalize " if s[:effects] =~ /normalize/
  command << "--audio-highpass 80 " if s[:effects] =~ /highpass/
  
  puts "Test #{current_test_number}/#{total_test_count}"
  puts "Running '#{command}'..."
  
  encode_threads = []
  start_time = Time.now
  stat_collector = StatCollector.new
  
  encode_threads << Thread.new do
    `#{command}`
  end
  
  while encode_threads.length > 0
    iteration_start_time = Time.now

    stat_collector.collect

    encode_threads.each do |t|
      if !t.alive?
        t.join
        encode_threads.delete(t)
      end
    end
    
    STDOUT.print '.'
    STDOUT.flush

    sleep (1 - (Time.now - iteration_start_time) - 0.01)
  end
  
  end_time = Time.now

  puts
  puts "Done! (%0.2f)" % (end_time-start_time)

  puts
  stat_collector.display
  puts
  
  stat_collector.save(@save_file_name, :worker_type => $worker_type, :command => command, :baseline => @codec_baselines[s[:codec]])
end

combined_tests.settings_grid.each do |s|
  current_test_number += 1
  
  command = "zenengine /tmp/combined_#{s[:input_width]}_2997_600s.mp4 --beta-aac-encoder --audio-codec aac --video-codec #{s[:codec]} --upscale --width #{s[:output_width]} "
  
  puts "Test #{current_test_number}/#{total_test_count}"
  puts "Running '#{command}' with concurrency of #{s[:concurrency]}..."
  
  if s[:codec] == 'vp6'
    ignore_flix = false
  else
    ignore_flix = true
  end
  
  encode_threads = []
  start_time = Time.now
  stat_collector = StatCollector.new(ignore_flix)

  s[:concurrency].times do
    encode_threads << Thread.new do
      `#{command}`
    end
  end
  
  while encode_threads.length > 0
    iteration_start_time = Time.now

    stat_collector.collect

    encode_threads.each do |t|
      if !t.alive?
        t.join
        encode_threads.delete(t)
      end
    end
    
    STDOUT.print '.'
    STDOUT.flush

    sleep (1 - (Time.now - iteration_start_time) - 0.01)
  end
  
  end_time = Time.now

  puts
  puts "Done! (%0.2f)" % (end_time-start_time)

  puts
  stat_collector.display
  puts
  
  stat_collector.save(@save_file_name, :worker_type => $worker_type, :concurrency => s[:concurrency], :command => command, :baseline => @codec_baselines[s[:codec].to_s+'/aac'])
end


puts "SAVE FILE NAME: #{@save_file_name}"

