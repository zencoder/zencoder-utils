
# Helpers for writing dumper tools.


#
######################### Utilities #########################
#

# Simple util to print an error message and quit.
def error(msg); puts msg; exit; end

class String
  # Turn the string of data into a standard hex string.
  def hex
    unpack('H*').first.scan(/../).join(' ')
  end
end


#
######################### IO Helpers #########################
#

module IoHelpers

  # Big-Endian Unsigned Readers
  def ui8; read(1).unpack('C').first; end
  def ui16; read(2).unpack('n').first; end
  def ui24; ("\000" + read(3)).unpack('N').first; end
  def ui32; read(4).unpack('N').first; end
  def ui64; read(8).unpack('NN').inject(0) { |s,v| (s << 32) + v }; end

  # Big-Endian Signed Readers
  def si8; read(1).unpack('c').first; end
  def si16; read(2).unpack('cC').inject(0) { |s,v| (s << 8) + v }; end
  def si24; read(3).unpack('cCC').inject(0) { |s,v| (s << 8) + v }; end
  def si32; read(4).unpack('cCCC').inject(0) { |s,v| (s << 8) + v }; end
  def si64; read(8).unpack('cCCCCCCC').inject(0) { |s,v| (s << 8) + v }; end
  
  # Big-Endian Float Readers
  def f32; read(4).unpack('g').first; end
  def f64; read(8).unpack('G').first; end

  # Little-Endian Unsigned Readers (Assuming Intel 64-bit architecture)
  def byte; read(1).unpack('C').first; end
  def word; read(2).unpack('v').first; end
  def dword; read(4).unpack('V').first; end
  def qword; read(8).unpack('Q').first; end
  
  # Little-Endian Signed Readers (Assuming Intel 64-bit architecture)
  def char; read(1).unpack('c').first; end
  def short; read(2).unpack('s').first; end
  def int; read(4).unpack('l').first; end
  def long; read(8).unpack('q').first; end

  # Little-Endian Float Readers
  def single; read(4).unpack('e').first; end
  def double; read(8).unpack('E').first; end

  # Fixed-point, 8.8
  def fixed16; ui16.to_f / (2**8); end

  # Fixed-point, 16.16
  def fixed32; ui32.to_f / (2**16); end
  
  # Fixed-point, 2.30
  def fixed32_2; ui32.to_f / (2**30); end

  # Fixed-point, 32.32
  def fixed64; ui64.to_f / (2**32); end
  
  def guid; parts = read(16).unpack('VvvnNn'); sprintf('%08x-%04x-%04x-%04x-%08x%04x', *parts).upcase; end
  def fourcc; read(4).unpack('a*').first; end
  
  def read_wchars(count)
    buffer = []
    count.times do
      buffer << byte
      trash = byte
    end
    buffer.pop if buffer.last == 0
    buffer.pack('C*')
  end
end

class IO
  include IoHelpers
end
require 'stringio'
class StringIO
  include IoHelpers
end


#
######################### Colored Output #########################
#

# Colored print...
def cprint(message, color = :none)
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
  if colors[color]
    print "\x1b[1;#{colors[color]}m#{message}\x1b[0m"
  else
    print message
  end
end

def cputs(message, color)
  cprint(message+"\n", color)
end

# Just to show the colors, for reference.
def rainbow
  cprint "black,", :black
  cprint "dark_gray,", :dark_gray
  cprint "gray,", :gray
  cprint "dark_white,", :dark_white
  cputs "white", :white

  cprint "dark_purple,", :dark_purple
  cputs "purple", :purple
  cprint "dark_red,", :dark_red
  cputs "red", :red
  cprint "dark_yellow,", :dark_yellow
  cputs "yellow", :yellow
  cprint "dark_green,", :dark_green
  cputs "green", :green
  cprint "dark_cyan,", :dark_cyan
  cputs "cyan", :cyan
  cprint "dark_blue,", :dark_blue
  cputs "blue", :blue
end
