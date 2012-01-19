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


video_tests = ZenEngine::SettingsGrid.new([:kind, :concurrency, :video_bitrate, :codec])
audio_tests = ZenEngine::SettingsGrid.new([:concurrency, :codec])

@set = nil
mode = ARGV.shift
case mode
when '-a'
  @set = :audio
when '-v'
  @set = :video
when '-b'
  @set = :baselines
when '-c'
  @set = :compound
else
  puts "Please choose a set of tests!"
  exit
end

if @set == :video || @set == :baselines
  video_tests << { :kind => '4m', :concurrency => (1..6).to_a, :video_bitrate => '3000', :codec => 'h264' }
  video_tests << { :kind => '23m', :concurrency => (1..6).to_a, :video_bitrate => '1000', :codec => 'h264' }
  video_tests << { :kind => '30s', :concurrency => (1..6).to_a, :video_bitrate => '500', :codec => 'h264' }
end

if @set == :audio
  audio_tests << { :concurrency => (1..20).to_a, :codec => 'aac' }
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
  command = "zenengine /mnt/zenbench/30s_phone_2pass.mov --skip-audio --video-codec #{codec} --clip-length 1"
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
  command = "zenengine /mnt/zenbench/3m_audio.mp3 --skip-video --audio-codec #{codec} --clip-length 1"
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

  case s[:kind]
  when '4m'
    input_file = '4m_hd_2pass.mov'
  when '23m'
    input_file = '23m_sd_2pass.mov'
  when '30s'
    input_file = '30s_phone_2pass.mov'
  end

  if s[:video_bitrate] == 'audio'
    video_option = '--skip-video'
  else
    video_option = "--video-bitrate #{s[:video_bitrate]}"
  end

  command = "zenengine /mnt/zenbench/#{input_file} --audio-bitrate 96 #{video_option} "
  
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

  command = "zenengine /mnt/zenbench/3m_audio.mp3 --skip-video --audio-bitrate 96 "
  
  @stat_sets = []
  
  puts "Running '#{command}' with concurrency of #{s[:concurrency]}..."
  
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


if @set == :compound
  audio_concurrency_levels = [0, 2, 4, 8, 12, 16]

  audio_concurrency_levels.each do |audio_concurrency|
    puts "Running compound test with audio concurrency of #{audio_concurrency}..."

    video_command = "zenengine /mnt/zenbench/4m_hd_2pass.mov --audio-bitrate 96 --video-bitrate 3000"
    audio_command = "zenengine /mnt/zenbench/audio_3681_seconds.mp4 --audio-bitrate 96"

    commands = []
    commands << video_command
    audio_concurrency.times do
      commands << audio_command
    end

    @stat_sets = []
    $ignore_flix = true

    encode_threads = []
    $start_time = Time.now
    commands.each do |command|
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
    
    s = { :kind => 'compound', :video_command => video_command, :audio_command => audio_command, :audio_concurrency => audio_concurrency, :concurrency => audio_concurrency+1 }

    save_stats(s, "compound 4m_hd + #{audio_concurrency} * 3681s_audio")
  end

end
