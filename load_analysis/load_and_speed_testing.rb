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


SAMPLE_COMMAND = 'ps -eo pid,pcpu,rss,thcount,command | grep -i -E "x264|ffmpeg|mp4box|faac|zenengine|nero|flix|mplayer|mencoder"'
@stat_sets = []

def collect_stats
  stats = Hash.new(0.0)
  
  results = `#{SAMPLE_COMMAND}`.split(/\n/)
  stats[:time] = Time.now - $start_time

  procsets = {}
  results.each do |line|
    # # PID USER      PR  NI  VIRT  RES  SHR S %CPU %MEM    TIME+  COMMAND
    # pid,user,priority,nice,virt,res,shr,state,cpu,mem,time,command = line.split(' ',12)

    # PID %CPU %MEM THCNT COMMAND
    pid,cpu,mem,threads,command = line.split(' ',5)

    next if command =~ /grep|java -cp|^sh /
    next if command =~ /flix/ && (cpu.to_f == 0.0 || $ignore_flix)

    # Bad reporting sometimes.
    cpu = '100.0' if cpu.to_f > 999

    # STDOUT.puts "CPU=%3.1f, MEM=%6d: #{command}" % [cpu,mem]
    
    stats[:cpu] += cpu.to_f
    stats[:mem] += mem.to_f / 1024.0 # In megabytes.
    stats[:threads] += threads.to_i
    stats[:procs] += 1
  end
  
  @stat_sets << stats
end

def display_stats
  @stat_sets.each do |stats|
    puts "TIME=%06.2f CPU=%05.1f MEM=%06.1f PROCS=%03d THREADS=%03d" % [stats[:time], stats[:cpu], stats[:mem], stats[:procs], stats[:threads]]
    # puts "STATS: #{stats.inspect}"
  end
end

def save_stats(s, command)
  File.open("/tmp/load_test_results.txt", 'a') do |f|
    f.puts "*RESULT_START"
    f.puts "*SETTINGS: #{s.inspect}"
    f.puts "*COMMAND: #{command}"
    f.puts "*MAX_CPU: %0.1f" % @stat_sets.collect { |i| i[:cpu] }.max
    f.puts "*MAX_MEM: %0.1f" % @stat_sets.collect { |i| i[:mem] }.max
    f.puts "*MAX_PROCS: %d" % @stat_sets.collect { |i| i[:procs] }.max
    f.puts "*MAX_THREADS: %d" % @stat_sets.collect { |i| i[:threads] }.max
    @stat_sets.each do |stats|
      f.puts "#{stats.inspect}"
    end
    f.puts "*RESULT_END"
  end
end

def save_baseline(codec, time)
  File.open("/tmp/load_test_results.txt", 'a') do |f|
    f.puts "*BASELINE_START"
    f.puts "*CODEC: #{codec}"
    f.puts "*TIME: %0.2f" % time
    f.puts "*BASELINE_END"
  end
end




# for res in 640 1280 1920; do bin/zenengine ~/zen/example_files/tina_fey.mov --frame-rate 29.97 --width $res --upscale --skip-audio --clip-length 60 --quality 4 --filename tina_${res}_2997.mp4; done
# for fps in 15 59.94; do bin/zenengine ~/zen/example_files/tina_fey.mov --frame-rate $fps --width 1280 --upscale --skip-audio --clip-length 60 --quality 4 --filename tina_1280_$fps.mp4; done
# for file in bbb_1080p.mov earth.mov static.mp4; do bin/zenengine ~/zen/example_files/$file --frame-rate 29.97 --width 1280 --upscale --skip-audio --clip-length 60 --quality 4 --filename $file_1280_2997.mp4; done
# bin/zenengine ~/Desktop/static.mov --frame-rate 29.97 --width 1280 --upscale --skip-audio --clip-length 60 --quality 4 --filename static_1280_2997.mp4

# bin/zenengine ~/Desktop/static.mov --frame-rate 29.97 --width 1280 --upscale --skip-audio --clip-length 60 --quality 4 --filename static_1280_2997.mp4

# for rate in 22050 44100 48000; do bin/zenengine ~/file --skip-video --audio-quality 4 --audio-sample-rate $rate --audio-channels 2 --clip-length 900 --beta-aac-encoder --filename audio_${rate}_2.mp4; done
# for rate in 22050 44100 48000; do bin/zenengine ~/file --skip-video --audio-quality 4 --audio-sample-rate $rate --audio-channels 1 --clip-length 900 --beta-aac-encoder --filename audio_${rate}_1.mp4; done


video_tests = ZenEngine::SettingsGrid.new([:kind, :decoder, :input_rate, :output_rate, :input_width, :output_width, :concurrency, :speed, :quality, :watermark, :codec, :postprocess])
audio_tests = ZenEngine::SettingsGrid.new([:input_rate, :output_rate, :input_channels, :output_channels, :quality, :effects, :codec])

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
when '-b'
  @set = :baselines
else
  puts "Please choose a set of tests!"
  exit
end

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

if @set == :audio
  audio_tests << { :input_rate => [22050, 44100, 48000], :output_rate => [22050, 44100, 48000], :input_channels => [1,2], :output_channels => [1,2], :quality => 3, :effects => "none", :codec => ["aac", "mp3", "wma"] }
  audio_tests << { :input_rate => 44100, :output_rate => 44100, :input_channels => 2, :output_channels => 2, :quality => [1,2,3,4,5], :effects => "none", :codec => ["aac", "mp3", "wma"] }
  audio_tests << { :input_rate => 44100, :output_rate => 44100, :input_channels => 2, :output_channels => 2, :quality => 3, :effects => ["none", "normalize", "highpass", "normalize_highpass"], :codec => "aac" }
end

puts "VIDEO TESTS"
video_tests.settings_dump
puts

puts "AUDIO TESTS"
audio_tests.settings_dump
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
  save_baseline(codec, @codec_baselines[codec])
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
  save_baseline(codec, @codec_baselines[codec])
  puts "Done!  (%0.2f)" % @codec_baselines[codec]
end

exit if @set == :baselines

puts
puts

video_tests.settings_grid.each do |s|

  rate_suffix = s[:input_rate].to_s.gsub('.','')
  command = "zenengine /tmp/#{s[:kind]}_#{s[:input_width]}_#{rate_suffix}.mp4 --skip-audio --video-codec #{s[:codec]} --upscale --width #{s[:output_width]} "
  command << "--speed #{s[:speed]} --quality #{s[:quality]} --frame-rate #{s[:output_rate]} "
  command << "--use-mplayer-for-video " if s[:decoder] == 'mplayer'
  command << "--watermark-file /tmp/watermark.png " if s[:watermark] == 1
  command << "--autolevel " if s[:postprocess] =~ /autolevel/
  command << "--sharpen " if s[:postprocess] =~ /sharpen/
  
  puts "Running '#{command}' with concurrency of #{s[:concurrency]}..."
  
  @stat_sets = []
  if s[:codec] == 'vp6'
    $ignore_flix = false
  else
    $ignore_flix = true
  end
  
  encode_threads = []
  $start_time = Time.now
  s[:concurrency].times do
    encode_threads << Thread.new do
      `#{command}`
    end
  end
  
  
  while encode_threads.length > 0
    iteration_start_time = Time.now

    collect_stats

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
  
  $end_time = Time.now

  puts
  puts "Done! (%0.2f)" % ($end_time-$start_time)

  puts
  display_stats
  puts
  
  save_stats(s, command)
  
end


audio_tests.settings_grid.each do |s|
  # :input_rate, :output_rate, :input_channels, :output_channels, :quality, :effects, :codec

  command = "zenengine /tmp/audio_#{s[:input_rate]}_#{s[:input_channels]}.mp4 --skip-video --audio-codec #{s[:codec]} --beta-aac-encoder "
  command << "--audio-sample-rate #{s[:output_rate]} --audio-channels #{s[:output_channels]} --audio-quality #{s[:quality]} "
  command << "--audio-normalize " if s[:effects] =~ /normalize/
  command << "--audio-highpass 80 " if s[:effects] =~ /highpass/
  
  @stat_sets = []
  
  puts "Running '#{command}'..."
  
  encode_threads = []
  $start_time = Time.now
  encode_threads << Thread.new do
    `#{command}`
  end
  
  
  while encode_threads.length > 0
    iteration_start_time = Time.now

    collect_stats

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
  
  $end_time = Time.now

  puts
  puts "Done! (%0.2f)" % ($end_time-$start_time)

  puts
  display_stats
  puts
  
  save_stats(s, command)
  
end

