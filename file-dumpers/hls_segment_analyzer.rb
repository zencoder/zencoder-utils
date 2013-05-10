#!/usr/bin/env ruby

#
# MPG Dump
#

#
# Specs from:
#   http://www.mpucoder.com/DVD/index.html
#
#   http://en.wikipedia.org/wiki/MPEG_program_stream
#   http://en.wikipedia.org/wiki/Elementary_stream
#   http://www.andrewduncan.ws/MPEG/MPEG-1.ps
#   http://dvd.sourceforge.net/dvdinfo/mpeghdrs.html
#   http://dvd.sourceforge.net/dvdinfo/pci_pkt.html
#   http://dvd.sourceforge.net/dvdinfo/dsi_pkt.html
#   http://en.wikibooks.org/wiki/Inside_DVD-Video/MPEG_Format
#   http://www.moviesmac.com/tutorial/vob-format.html
#   http://flavor.sourceforge.net/samples/mpeg2ps.htm
#   http://knol.google.com/k/mpeg-2-transmission

require 'stringio'

def error(msg); puts msg; exit; end

$DISABLE_COLOR = !STDOUT.tty?

# Colored print...
def cprint(message, color = $DEFAULT_COLOR)
  colors = {
    :black => '0;30',
    :dark_gray => '1;30',
    :dark_grey => '1;30',
    :gray => '0',
    :grey => '0',
    :dark_red => '0;31',
    :red => '1;31',
    :dark_green => '0;32',
    :green => '1;32',
    :dark_yellow => '0;33',
    :yellow => '1;33',
    :dark_blue => '0;34',
    :blue => '1;34',
    :dark_purple => '0;35',
    :dark_magenta => '0;35',
    :purple => '1;35',
    :magenta => '1;35',
    :dark_cyan => '0;36',
    :cyan => '1;36',
    :dark_white => '0;37',
    :white => '1;37'
  }
  if colors[color] && !$DISABLE_COLOR
    print "\x1b[1;#{colors[color]}m#{message}\x1b[0m"
  else
    print message
  end
end

def cputs(message, color = $DEFAULT_COLOR)
  cprint(message+"\n", color)
end

def with_color(color, &block)
  prev_color = $DEFAULT_COLOR
  $DEFAULT_COLOR = color
  block.call
ensure
  $DEFAULT_COLOR = prev_color
end


module IoHelpers
  def ui8; read2(1).unpack('C').first; end
  def ui16; read2(2).unpack('n').first; end
  def ui32; read2(4).unpack('N').first; end
  def ui24; ("\000" + read2(3)).unpack('N').first; end

  def peek(size)
    @peek_buffer ||= ""
    if @peek_buffer.length < size
      new_bytes = read(size - @peek_buffer.length)
      @peek_buffer << new_bytes if new_bytes
    end
    @peek_buffer[0,size]
  end
  
  # Set up a read method that uses the peek buffer.
  def read2(size)
    return read(size) unless @peek_buffer && @peek_buffer.length > 0

    result = ''
    result << @peek_buffer[0,size]
    @peek_buffer = @peek_buffer[result.length .. -1]
    size = size - result.length
    result << read(size).to_s if size > 0

    result
  end

  def pos2
    pos - @peek_buffer.to_s.length
  end

  def find_next_start_code(start_offset = 0, skip_escapes = false)
    peek_size = 1024
    peek_size *= 2 while peek_size < (start_offset + 3)

    upcoming_bytes = peek(peek_size)
    start_code_index = nil

    # Keep going until we find it, or run out of buffer.
    while true
      start_code_index = upcoming_bytes.index("\x00\x00\x01", start_offset)
      break if start_code_index.nil?

      # Make sure this isn't an escaped start code.
      if skip_escapes
        while start_code_index && start_code_index > 0 && upcoming_bytes[start_code_index - 1, 3] == "\x00\x00\x00"
          start_offset = start_code_index + 3
          start_code_index = upcoming_bytes.index("\x00\x00\x01", start_offset)
        end
      end

      break if start_code_index || upcoming_bytes.length < peek_size

      peek_size *= 2
      upcoming_bytes = peek(peek_size)
    end

    return start_code_index
  end
end

class IO
  include IoHelpers
end
class StringIO
  include IoHelpers

  def append(string)
    orig_pos = pos
    seek(0, IO::SEEK_END)
    write(string)
    seek(orig_pos)
  end
end

class Bitstream
  attr_accessor :bit_offset, :data
  
  def initialize(data_string, starting_byte_offset = 0)
    @data = data_string
    @bit_offset = 0
    @pos = starting_byte_offset
  end

  def nextbits(count)
    raise "nextbits of more than 16 not implemented" if count > 16
    getbits_internal(count, false)
  end

  # Return an integer of the next _count_ bits and increment @bit_offset so that
  # subsequent calls will get following bits.
  def getbits(count)
    value = 0
    while count > 16
      value += getbits_internal(16)
      count -= 16
      value = value << [count,16].min
    end
    value += getbits_internal(count)
  end
  
  def skipbits(count)
    @bit_offset += count
  end
  
  # Do getbits, with up to 16 bits.
  def getbits_internal(count, increment_position = true)
    return 0 if count > 16 || count < 1
    byte = @bit_offset / 8
    bit  = @bit_offset % 8
    val = (@data[@pos + byte].to_i << 16) + (@data[@pos + byte + 1].to_i << 8) + @data[@pos + byte + 2].to_i
    val = (val << bit) & 16777215
    val = val >> (24 - count)

    @bit_offset += count if increment_position
    return val
  end
  
  def append(data_string)
    @data << data_string
  end
  
  # Remove any data that we've moved past already, so we don't build up too much in memory.
  def pop
    byte = @bit_offset / 8
    bit = @bit_offset % 8
    
    @pos += byte
    @bit_offset = bit
    
    if @pos > 0
      @data = @data[@pos..-1]
      @pos = 0
    end
    
    true
  end

  def read(size)
    if @bit_offset % 8 > 0
      puts "Warning: Reading at non-aligned bitstream offset"
    end
    byte = @bit_offset / 8
    @bit_offset = [@bit_offset + size * 8, @data.length * 8].min
    @data[byte,size]
  end

  def remaining_bits
    @data.length * 8 - @bit_offset
  end
end

STREAM_TYPES = {
  0x00 => "Picture",
  0xB0 => "Reserved",
  0xB1 => "Reserved",
  0xB2 => "User Data",
  0xB3 => "Sequence Header",
  0xB4 => "Sequence Error",
  0xB5 => "Extension",
  0xB6 => "Reserved",
  0xB7 => "Sequence End",
  0xB8 => "Group of Pictures",
  0xB9 => "Program End",
  0xBA => "Pack Header",
  0xBB => "System Header",
  0xBC => "Program Stream Map",
  0xBD => "Private Stream 1 (Non-MPEG Audio, Subpictures)",
  0xBE => "Padding Stream",
  0xBF => "Private Stream 2 (Navigation Data)",
  0xFF => "Program Stream Directory"
}
0x01.upto(0xAF) { |i| STREAM_TYPES[i] = "Slice" }
0xC0.upto(0xDF) { |i| STREAM_TYPES[i] = "Audio Stream #{i-0xC0}" }
0xE0.upto(0xEF) { |i| STREAM_TYPES[i] = "Video Stream #{i-0xE0}" }
0xFA.upto(0xFE) { |i| STREAM_TYPES[i] = "Reserved" }

# Regarding private stream 1:
    # sub-stream 0x20 to 0x3f are subpictures
    # sub-stream 0x80 to 0x87 are audio (AC3, DTS, SDDS)
    # sub-stream 0xA0 to 0xA7 are LPCM audio

ASPECT_RATIO_TABLE = {
  0 => 'Forbidden',
  1 => '1:1',
  2 => '4:3',
  3 => '16:9',
  4 => '2.21:1'
}
ASPECT_RATIO_TABLE.default = 'Unknown'

FRAME_RATE_TABLE = {
  0 => 'Forbidden',
  1 => '24000/1001 = 23.976',
  2 => '24',
  3 => '25',
  4 => '30000/1001 = 29.97',
  5 => '30',
  6 => '50',
  7 => '60000/1001 = 59.94',
  8 => '60'
}
FRAME_RATE_TABLE.default = 'Unknown'

FRAME_TYPE_TABLE = {
  1 => 'I',
  2 => 'P',
  3 => 'B',
  4 => 'D'
}
FRAME_TYPE_TABLE.default = 'Unknown'

COLOR_PRIMS_TABLE = {
  0 => 'Forbidden',
  1 => 'BT.709',
  2 => 'Unspecified',
  3 => 'Reserved/future',
  4 => 'BT.470-6/NTSC 1953',
  5 => 'EBU Tech 3213',
  6 => 'SMPTE RP 145',
  7 => 'SMPTE 240M',
  8 => 'Generic film'
}
COLOR_PRIMS_TABLE.default = 'Unknown'

TRANSFER_CHARS_TABLE = {
  0 => 'Forbidden',
  1 => 'BT.709',
  2 => 'Unspecified',
  3 => 'Reserved/future',
  4 => 'Display gamma 2.2',
  5 => 'Display gamma 2.8',
  6 => 'BT.709', # Yes, a dupe.
  7 => 'SMPTE 240M',
  8 => 'Linear',
  9 => 'Log (10^2:1)',
  10 => 'Log (10^2.5:1)',
  11 => 'xvYCC',
  12 => 'BT.1361'
}
TRANSFER_CHARS_TABLE.default = 'Reserved'

MATRIX_COEFFS_TABLE = {
  0 => 'Forbidden/BR',
  1 => 'BT.709',
  2 => 'Unspecified',
  3 => 'Reserved/future',
  4 => 'BT.601',
  5 => 'BT.601', # dupe
  6 => 'BT.601', # dupe
  7 => 'SMPTE 240M',
  8 => "Y'CgCo"
}
MATRIX_COEFFS_TABLE.default = 'Reserved'


def decode_pack_header
  puts "Found 0x000001BA = Pack Header (10 bytes + stuffing):"
  pack_header = Bitstream.new($segment_file.read2(10))
  scr = 0
  puts "  marker bits:  #{pack_header.getbits(2)}"
  scr_bits = pack_header.getbits(3)
  scr += (scr_bits << 30)
  puts "  scr(32-30):   #{scr_bits}"
  puts "  marker bit:   #{pack_header.getbits(1)}"
  scr_bits = pack_header.getbits(15)
  scr += (scr_bits << 15)
  puts "  scr(29-15):   #{pack_header.getbits(15)}"
  puts "  marker bit:   #{pack_header.getbits(1)}"
  scr_bits = pack_header.getbits(15)
  scr += scr_bits
  puts "  scr(14-0):    #{scr_bits}"
  puts "  marker bit:   #{pack_header.getbits(1)}"
  scr_ext = pack_header.getbits(9)
  puts "  scr ext:      #{scr_ext}"
  puts "  marker bit:   #{pack_header.getbits(1)}"
  puts "  bit rate:     #{pack_header.getbits(22)} * 50 bytes per second"
  puts "  marker bits:  #{pack_header.getbits(2)}"
  puts "  reserved:     #{pack_header.getbits(5)}"
  stuffing_len = pack_header.getbits(3)
  puts "  stuffing len: #{stuffing_len}"
  puts "  SCR Time: %0.6f" % (scr / 90000.0 + scr_ext / 27000000.0)
  stuffing = $segment_file.read2(stuffing_len)
end

def decode_system_header
  header_len = $segment_file.ui16
  puts "Found 0x000001BB = System Header (#{header_len} bytes):"
  system_header = Bitstream.new($segment_file.read2(header_len))
  system_header.getbits(1) # marker
  puts "  rate bound: #{system_header.getbits(22)}"
  system_header.getbits(1) # marker
  puts "  audio bound: #{system_header.getbits(6)}"
  puts "  fixed bit rate?: #{system_header.getbits(1)}"
  puts "  constrained params?: #{system_header.getbits(1)}"
  puts "  system audio lock?: #{system_header.getbits(1)}"
  puts "  system video_lock?: #{system_header.getbits(1)}"
  system_header.getbits(1) # marker
  puts "  video bound: #{system_header.getbits(5)}"
  puts "  packet rate restriction?: #{system_header.getbits(1)}"
  system_header.getbits(7) # reserved

  while system_header.nextbits(1) == 1
    stream_id = system_header.getbits(8)

    if stream_id < 0xBC && ![0xB8, 0xB9].include?(stream_id)
      puts "  BAD STREAM_ID IN SYSTEM HEADER: 0x#{stream_id.to_s(16)}"
    end

    puts "  Stream with ID: #{stream_id} (0x#{stream_id.to_s(16)})#{' = ' if STREAM_TYPES[stream_id]}#{STREAM_TYPES[stream_id]}"
    system_header.getbits(2) # marker/reserved?
    puts "    p_std_buffer_bound_scale: #{system_header.getbits(1)}"
    puts "    p_std_buffer_size_bound: #{system_header.getbits(13)}"
  end
end

def decode_sequence_header
  puts "Found 0x000001B3 = Sequence Header:"
  seq_header = Bitstream.new($segment_file.read2(8))
  width = seq_header.getbits(12)
  height = seq_header.getbits(12)
  aspect_ratio = seq_header.getbits(4)
  frame_rate = seq_header.getbits(4)
  bit_rate = seq_header.getbits(18)
  marker = seq_header.getbits(1)
  buffer_size = seq_header.getbits(10)
  constrained_parameters = seq_header.getbits(1)

  puts "  Width:        #{width}"
  puts "  Height:       #{height}"
  puts "  Aspect Ratio: #{aspect_ratio} (#{ASPECT_RATIO_TABLE[aspect_ratio]})"
  puts "  Frame Rate:   #{frame_rate} (#{FRAME_RATE_TABLE[frame_rate]})"
  puts "  Bit Rate:     #{bit_rate * 400} bits/sec"
  puts "  Buffer Size:  #{buffer_size * 2048} bytes"

  # Read the last couple flags and their 64-byte tables, if present.
  intra_matrix_flag = seq_header.getbits(1)
  if intra_matrix_flag == 1
    $segment_file.read2(63)
    last_byte = $segment_file.read2(1)[0]
    non_intra_matrix_flag = last_byte & 1
  else
    non_intra_matrix_flag = seq_header.getbits(1)
  end

  if non_intra_matrix_flag == 1
    $segment_file.read2(64)
  end
end

def decode_extension
  puts "Found 0x000001B5 = Extension:"
  leading_byte = $segment_file.peek(1).unpack('C').first
  kind = leading_byte >> 4

  case kind
  when 1
    puts "  Sequence Extension"
    ext_data = Bitstream.new($segment_file.read2(6))
    junk = ext_data.getbits(4)
    profile_and_level = ext_data.getbits(8)
    progressive_sequence = ext_data.getbits(1)
    chroma_format = ext_data.getbits(2)
    horiz_size_ext = ext_data.getbits(2)
    vert_size_ext = ext_data.getbits(2)
    bitrate_ext = ext_data.getbits(12)
    junk = ext_data.getbits(1)
    vbv_bufsize_ext = ext_data.getbits(8)
    low_delay = ext_data.getbits(1)
    fps_n_ext = ext_data.getbits(2)
    fps_d_ext = ext_data.getbits(5)

    puts "  Profile/Level:   #{profile_and_level}"
    puts "  Progressive Seq: #{progressive_sequence}"
    puts "  Chroma Format:   #{chroma_format}"
    puts "  Horiz Size Ext:  #{horiz_size_ext}"
    puts "  Vert Size Ext:   #{vert_size_ext}"
    puts "  Bitrate Ext:     #{bitrate_ext}"
    puts "  VBV Bufsize Ext: #{vbv_bufsize_ext}"
    puts "  Low Delay:       #{low_delay}"
    puts "  FPS N Ext:       #{fps_n_ext}"
    puts "  FPS D Ext:       #{fps_d_ext}"

  when 2
    puts "  Sequence Display Extension"

    # Good info on interpretation here: http://www.dvmp.co.uk/mod-video-file-format.htm

    has_color_desc = (leading_byte & 1) > 0
    if has_color_desc
      ext_data = Bitstream.new($segment_file.read2(8))
    else
      ext_data = Bitstream.new($segment_file.read2(5))
    end
    junk = ext_data.getbits(4)
    video_format = ext_data.getbits(3)
    color_desc_flag = ext_data.getbits(1)
    if has_color_desc
      color_prims = ext_data.getbits(3)
      transfer_chars = ext_data.getbits(3)
      matrix_coeffs = ext_data.getbits(3)
    end
    display_horiz_size = ext_data.getbits(14)
    junk = ext_data.getbits(1)
    display_vert_size = ext_data.getbits(14)

    puts "  Video Format:       #{video_format}"
    puts "  Color Desc Flag:    #{color_desc_flag}"
    if has_color_desc
      puts "  Color Prims:        #{color_prims}"
      puts "  Transfer Chars:     #{transfer_chars}"
      puts "  Matrix Coeffs:      #{matrix_coeffs}"
    end
    puts "  Display Horiz Size: #{display_horiz_size}"
    puts "  Display Vert Size:  #{display_vert_size}"
    
  when 8
    puts "  Picture Coding Extension (Not yet decoded...)" # See http://dvd.sourceforge.net/dvdinfo/mpeghdrs.html#ext
    ext_data = Bitstream.new($segment_file.read2(8))
    
  else
    puts "  Unknown extension: #{kind}"
  end
end

def decode_gop
  puts "Found 0x000001B8 = Group of Pictures:"
  gop_header = Bitstream.new($segment_file.read2(4))
  drop_frame_flag = gop_header.getbits(1)
  t_hour = gop_header.getbits(5)
  t_min = gop_header.getbits(6)
  marker = gop_header.getbits(1)
  t_sec = gop_header.getbits(6)
  t_frame = gop_header.getbits(6)
  closed_gop = gop_header.getbits(1)
  broken_gop = gop_header.getbits(1)
  puts "  Drop?: #{drop_frame_flag}"
  puts "  Hour:  #{t_hour}"
  puts "  Min:   #{t_min}"
  puts "  Sec:   #{t_sec}"
  puts "  Frame: #{t_frame}"
  puts "  Closed? #{closed_gop}"
  puts "  Broken? #{broken_gop}"
end

def decode_picture_header
  puts "Found 0x00000100 = Picture Header:"
  pic_header = Bitstream.new($segment_file.read2(4))
  
  seq_number = pic_header.getbits(10)
  frame_type = pic_header.getbits(3)
  vbv_delay = pic_header.getbits(16)
  
  puts "  Sequence Number: #{seq_number}"
  puts "  Frame Type: #{frame_type} (#{FRAME_TYPE_TABLE[frame_type]})"
  puts "  VBV Delay: #{vbv_delay}"
  
  if frame_type == 2 || frame_type == 3
    pic_header.append($segment_file.read2(1)) unless pic_header.remaining_bits >= 4

    full_pel_forward_vector = pic_header.getbits(1)
    forward_f_code = pic_header.getbits(3)
    puts "  Forward Vector: #{full_pel_forward_vector}"
    puts "  Forward F Code: #{forward_f_code}"
  end
  
  if frame_type == 3
    pic_header.append($segment_file.read2(1)) unless pic_header.remaining_bits >= 4

    full_pel_backward_vector = pic_header.getbits(1)
    backward_f_code = pic_header.getbits(3)
    puts "  Backward Vector: #{full_pel_backward_vector}"
    puts "  Backward F Code: #{backward_f_code}"
  end
  
  # At this point there are possibly extra bits in sequence...  Ignored for now.
  
end

def decode_pes_header(data, pid)
  ext_header = Bitstream.new(data)
  # http://dvd.sourceforge.net/dvdinfo/pes-hdr.html
  ext_header.skipbits(5) # For now...
  data_alignment_indicator = ext_header.getbits(1)
  copyright = ext_header.getbits(1)
  is_original = ext_header.getbits(1)
  pts_dts_flags = ext_header.getbits(2)
  escr_flag = ext_header.getbits(1)
  es_rate_flag = ext_header.getbits(1)
  dsm_trick_mode_flag = ext_header.getbits(1)
  additional_copy_info_flag = ext_header.getbits(1)
  crc_flag = ext_header.getbits(1)
  pes_ext_flag = ext_header.getbits(1)
  data_len = ext_header.getbits(8)

  puts "PES: aligned=#{data_alignment_indicator}, escr=#{escr_flag}, es_rate=#{es_rate_flag}"
  pts = nil
  dts = nil
  if pts_dts_flags >= 2
    pts_b = ext_header
    pts = 0
    marker = pts_b.getbits(4)
    if marker < 2 || marker > 3
      puts "  INVALID PTS PREFIX BITS"
    end
    scr_bits = pts_b.getbits(3)
    pts += (scr_bits << 30)
    pts_b.skipbits(1)
    scr_bits = pts_b.getbits(15)
    pts += (scr_bits << 15)
    pts_b.skipbits(1)
    scr_bits = pts_b.getbits(15)
    pts += scr_bits
    pts_b.getbits(1)

    pts /= 90000.0
    puts "  PTS: %0.6f" % pts

    if pts_dts_flags == 3
      dts_b = ext_header

      dts = 0
      marker = dts_b.getbits(4)
      if marker != 1
        puts "  INVALID DTS PREFIX BITS"
      end
      scr_bits = dts_b.getbits(3)
      dts += (scr_bits << 30)
      dts_b.skipbits(1)
      scr_bits = dts_b.getbits(15)
      dts += (scr_bits << 15)
      dts_b.skipbits(1)
      scr_bits = dts_b.getbits(15)
      dts += scr_bits
      dts_b.getbits(1)

      dts /= 90000.0
      puts "  DTS: %0.6f" % dts
    end
  end

  escr = nil
  if escr_flag == 1
    skip = ext_header.getbits(2)
    escr = 0
    scr_bits = ext_header.getbits(3)
    escr += (scr_bits << 30)
    ext_header.skipbits(1)
    scr_bits = ext_header.getbits(15)
    escr += (scr_bits << 15)
    ext_header.skipbits(1)
    scr_bits = ext_header.getbits(15)
    escr += scr_bits
    ext_header.skipbits(1)

    escr *= 300
    scr_bits = ext_header.getbits(9)
    escr += scr_bits

    escr /= 27000000.0
    puts "  ESCR: %0.6f" % escr
  end

  es_rate = nil
  if es_rate_flag == 1
    ext_header.skipbits(1)
    es_rate = ext_header.getbits(22)
    ext_header.skipbits(2)
    es_rate *= 50 # Units are 50 bytes/sec
    puts "  ES Rate: #{es_rate} bytes/sec"
  end

  if pts || dts || escr || es_rate
    @program_stream_metadata[pid] ||= []
    @program_stream_metadata[pid] << {
      :kind => :pes,
      :byte_offset => @program_stream_data[pid] ? @program_stream_data[pid].pos2 : 0,
      :pts => pts,
      :dts => dts,
      :escr => escr,
      :es_rate => es_rate
    }
  end

  
end

def decode_private_stream_2
  len = $segment_file.ui16
  puts "Found 0x000001BF = Private Stream 2 / Navigation (#{len} bytes):"
  if len > 0
    kind = $segment_file.ui8
    case kind
      when 0
        kind_name = 'PCI'
      when 1
        kind_name = 'DSI'
      else
        kind_name = 'Unknown'
    end
    puts "  Kind: #{kind_name}"
    $segment_file.read2(len - 1)
  end
end

def read_ts_packet(segment_file)
  pos = segment_file.pos2
  packet = Bitstream.new(segment_file.read2(188))
  if packet.getbits(8) == 0x47
    with_color(:dark_gray) do
      # cputs "TS PACKET @ #{pos}"

      tei  = packet.getbits(1)
      pusi = packet.getbits(1)
      tp   = packet.getbits(1)
      pid  = packet.getbits(13)
      scrambled = packet.getbits(2)
      adaptation_present = packet.getbits(1)
      payload_present = packet.getbits(1)
      continuity_counter = packet.getbits(4)

      # cputs "  TEI:  #{tei}"
      # cputs "  PUSI: #{pusi}"
      # cputs "  PRIO: #{tp}"
      # cputs "  PID:  #{pid}"
      # cputs "  Scrambled: #{scrambled}"
      # cputs "  Has Adaptation? #{adaptation_present}"
      # cputs "  Has Payload? #{payload_present}"
      # cputs "  Cont. Count: #{continuity_counter}"

      if pusi == 1
        @program_stream_metadata[pid] ||= []
        @program_stream_metadata[pid] << {
          :kind => :pusi,
          :byte_offset => @program_stream_data[pid] ? @program_stream_data[pid].length : 0
        }
      end

      if adaptation_present == 1
        len_bytes = packet.getbits(8)
        adaptation = Bitstream.new(packet.read(len_bytes))

        discontinuous = adaptation.getbits(1)
        random_access = adaptation.getbits(1)
        es_priority = adaptation.getbits(1)
        pcr = adaptation.getbits(1)
        opcr = adaptation.getbits(1)
        splicing_point = adaptation.getbits(1)
        private_data = adaptation.getbits(1)
        adaptation_extension = adaptation.getbits(1)

        # cputs "  Adaptation Extension:"
        # cputs "    Length: #{len_bytes}"
        # cputs "    Discontinuous: #{discontinuous}"
        # cputs "    Random Access: #{random_access}"
        # cputs "    PCR? #{pcr}"
        # cputs "    OPCR? #{opcr}"
        # cputs "    splicing_point: #{splicing_point}"
        # cputs "    private_data: #{private_data}"
        # cputs "    adaptation_extension: #{adaptation_extension}"

        if pcr == 1
          pcr_base = adaptation.getbits(33)
          pcr_pad = adaptation.getbits(6)
          pcr_ext = adaptation.getbits(9)
          cputs "    PCR: #{pcr_base},#{pcr_pad},#{pcr_ext} = #{sprintf('%0.6f', (pcr_base * 300 + pcr_ext) / 27000000.0)}"
          @program_stream_metadata[pid] ||= []
          @program_stream_metadata[pid] << {
            :kind => :pcr, 
            :pcr => (pcr_base * 300 + pcr_ext) / 27000000.0,
            :byte_offset => @program_stream_data[pid] ? @program_stream_data[pid].length : 0
          }
        end
        if opcr == 1
          opcr_base = adaptation.getbits(33)
          opcr_pad = adaptation.getbits(6)
          opcr_ext = adaptation.getbits(9)
          cputs "    OPCR: #{opcr_base},#{opcr_pad},#{opcr_ext} = #{sprintf('%0.6f', (opcr_base * 300 + opcr_ext) / 27000000.0)}"
        end
      end

      if payload_present
        byte_count = (packet.remaining_bits / 8)
        # cputs "  Adding #{byte_count} bytes to program #{pid} stream."
        @program_stream_data[pid] ||= StringIO.new('')
        @program_stream_data[pid].append(packet.read(188)) # read the rest
      end
      # puts
    end
  else
    puts "NOT AN MPEG-TS PACKET!"
  end
end

def read_pes_packet(packetized_stream, pid)
  start_code_offset = packetized_stream.find_next_start_code
  while start_code_offset
    # Make sure we have at least 6 bytes of packet to worker with.
    break unless packetized_stream.length >= (start_code_offset + 6)
    
    # Discard data until the start code.
    if start_code_offset > 0
      puts "Discarding #{start_code_offset} bytes before next start code."
      packetized_stream.read2(start_code_offset)
    end

    pes_header = packetized_stream.peek(6)
    packet_length = pes_header[4,2].unpack('n').first

    if packet_length == 0
      md = @program_stream_metadata[pid]
      if md.nil?
        puts "Packet length zero, but no metadata for pid!"
        return nil
      end
      next_pusi = md.detect { |data| data[:kind] == :pusi && data[:byte_offset] > packetized_stream.pos2 }
      if next_pusi.nil?
        puts "Packet length zero, but no further packet unit start indicators found!"
        return nil
      end
      next_pusi_offset = next_pusi[:byte_offset] - packetized_stream.pos2

      subsequent_start_code_offset = packetized_stream.find_next_start_code(next_pusi_offset, false)
      if subsequent_start_code_offset
        packet_length = subsequent_start_code_offset - 6
        puts "Determined packet length to be #{packet_length}"
      else
        break
      end
    end

    # If we've got data for the whole packet, then read it.
    if (packet_length + 6) <= packetized_stream.length
      kind = pes_header[3,1].unpack('C').first
      case kind
      when 0xC0..0xDF
        kind_name = "Audio"
      when 0xE0..0xEF
        kind_name = "Video"
      else
        kind_name = "Other"
      end

      if ['Audio','Video'].include?(kind_name)
        pes_header = packetized_stream.peek(28)
        decode_pes_header(pes_header[6,22], pid)
      end

      puts "Reading and discarding whole #{kind_name} PES packet at #{packetized_stream.pos2} with length #{packet_length}"

      packet_data = packetized_stream.read2(packet_length + 6)
    else
      # Not enough data for packet.
      break
    end

    start_code_offset = packetized_stream.find_next_start_code
  end
end

# E0 FF 00 00 00 08
# 1110 0000
# 1111 1111

# 0000 0000
# 0000 0000

# 0000 0000
# 0000 1000

# 80 BD 00 00 02 E0 00 00
# 1000 0000
# 1011 1101
# 0000 0000
# 0000 0000
# 0000 0010
# 1110 0000
# 0000 0000
# 0000 0000

# B3 9C F3 E9

def decode_ps_stream(stream)
  while start_code = stream.find_next_start_code
    case start_code[3]
    when 0x00
      decode_picture_header
    when 0xB3
      decode_sequence_header
    when 0xB5
      decode_extension
    when 0xB8
      decode_gop
    when 0xBA
      decode_pack_header
    when 0xBB
      decode_system_header
    when 0xBF
      decode_private_stream_2
    when 0xC0..0xEF
      decode_pes_header(start_code[3])
    else
      if STREAM_TYPES[start_code[3]]
        puts "Found Start Code: 0x00000#{start_code.unpack('N').first.to_s(16)} = #{STREAM_TYPES[start_code[3]]}"
      else
        puts "Unknown Start Code: 0x00000#{start_code.unpack('N').first.to_s(16)}"
      end
    end
    puts
  end
end


def analyze_segment(segment_file)
  first_byte = segment_file.peek(1)
  raise "Not a TS segment file!" unless first_byte[0,1] == "\x47"

  while !segment_file.eof?
    read_ts_packet(segment_file)
  end
end

def analyze_program_streams
  @program_stream_data.keys.sort.each do |pid|
    puts "Analyzing program stream #{pid}..."
    length = read_pes_packet(@program_stream_data[pid], pid)
  end
end

#######################################################################

@program_stream_metadata = {}
@program_stream_data = {}

error "Please specify an m3u8 file to inspect." unless ARGV.length > 0

input_filename = ARGV.first
error "Input file not found." unless File.exist?(input_filename)

index_file = File.open(input_filename)
signature = index_file.gets
raise "Not an m3u8 file!" unless signature =~ /^#EXTM3U/

while (line = index_file.gets)
  next if line =~ /^#/

  full_name = File.join(File.dirname(input_filename), line.chomp)
  puts "Analyzing segment file '#{full_name}'..."
  raise "Segment file '#{full_name}' not found!" unless File.exist?(full_name)
  $segment_file = File.open(full_name)

  analyze_segment($segment_file)

  analyze_program_streams

  
  # break # JUST FOR DEBUGGING
end

@program_stream_metadata.keys.sort.each do |pid|
  puts
  puts "METADATA FOR PROGRAM #{pid}"
  @program_stream_metadata[pid].sort_by { |md| md[:byte_offset] }.each do |md|
    case md[:kind]
    when :pcr
      puts "Offset: %8d - PCR: %0.6f" % [md[:byte_offset], md[:pcr]]
    when :pusi
      puts "Offset: %8d - PUSI" % [md[:byte_offset], md[:pcr]]
    when :pes
      info = ''
      info << (", DTS=%0.6f" % [md[:dts]]) if md[:dts]
      info << (", PTS=%0.6f" % [md[:pts]]) if md[:pts]
      info << (", ESCR=%0.6f" % [md[:escr]]) if md[:escr]
      info << (", ES_RATE=%d" % [md[:es_rate]]) if md[:es_rate]
      puts "Offset: %8d - PES#{info}" % [md[:byte_offset]]
    end
  end
  puts
end

exit

if format == :ts
  $ps_data = StringIO.new('')
  while !$segment_file.eof?
    read_ts_packet
    begin
      while start_code = $ps_data.find_next_start_code
        if STREAM_TYPES[start_code[3]]
          cputs "Found Start Code: 0x00000#{start_code.unpack('N').first.to_s(16)} = #{STREAM_TYPES[start_code[3]]}", :yellow
        else
          cputs "Unknown Start Code: 0x00000#{start_code.unpack('N').first.to_s(16)}", :red
        end
        puts
      end
    rescue
      nil
    end
  end
else
  while start_code = $segment_file.find_next_start_code
    case start_code[3]
    when 0x00
      decode_picture_header
    when 0xB3
      decode_sequence_header
    when 0xB5
      decode_extension
    when 0xB8
      decode_gop
    when 0xBA
      decode_pack_header
    when 0xBB
      decode_system_header
    when 0xBF
      decode_private_stream_2
    when 0xC0..0xEF
      decode_pes_header(start_code[3])
    else
      if STREAM_TYPES[start_code[3]]
        puts "Found Start Code: 0x00000#{start_code.unpack('N').first.to_s(16)} = #{STREAM_TYPES[start_code[3]]}"
      else
        puts "Unknown Start Code: 0x00000#{start_code.unpack('N').first.to_s(16)}"
      end
    end
    puts
  end
end
