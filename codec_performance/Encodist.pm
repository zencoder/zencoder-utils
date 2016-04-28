#!/usr/bin/perl -w

package Encodist;
use strict;
use Time::HiRes;
use Benchmark ':hireswallclock';

sub new
{
  my $class = shift; # $_[0] contains the class name
  my @com = @_;
  my $self = {};

  bless( $self, $class );

  $self->{name} = $class;
  $self->{settings} = \@com;
  $self->_init();

  return $self;
}

sub set_input_file 
{
  my $self = shift;
  my $infile = shift;
  
  die "input file not found: $infile\n" unless (-f $infile);
  $self->{infile} = $infile;

  return $self;
}

sub set_output_file 
{
  my $self = shift;
  my $outfile = shift;

  open (OUT, ">$outfile") or die "can't open output file: $outfile\n";
  select OUT;

  return $self;
}

sub set_decode_settings 
{
  my $self = shift;
  my $dec_options = join(' ', @_);

  $self->{decode} = "ffmpeg -loglevel verbose -y " . $dec_options;
  #$self->{decode} .= "-r 24/1 -an -map 0:0 -pix_fmt yuv420p ";
  #$self->{decode} .= "-sws_flags lanczos -vf [in]scale=3840:1714,setsar=sar=1/1[processed] ";

  return $self;
}

sub run
{
  #overview: form command line, run codecs and track cpu time
  #collect the output: settings tested, times, num of frames, bitrate, psrn/ssim, output file size,
  #print the output in csv if output filename given else stdout
  my $self = shift;

  #verify input
  die "no input file given\n" unless defined ($self->{infile});
  my $infile = $self->{infile};

  #decoding settings
  my $decode;
  if ( !defined($self->{decode}) ) { #nothing provided, set some defaults
    my %dec_settings = ('-threads' => 4, '-t' => '15.00', '-ss' => '10.00');
    $self->set_decode_settings(%dec_settings);
  }
  $decode = $self->{decode};
  $decode .= " -i $infile -f yuv4mpegpipe -";

  #print "$self->{cl_base}\n\n";
  #print "@{ $_ }\n" for (@{$self->{cls}});
   
  #Log file
  open (LOG, ">encodist.log") or die "can't open log file: encodist.log\n";

  my @range_vars = keys (%{ $self->{ranges} });
  $_ =~ s/--// for (@range_vars);
  print "#n, ",join(", ",@range_vars),", ";
  print "cpu, real, frames, bitrate, psnr\n";

  my $suf = $self->{encoder} eq 'x265' ? 'hevc' : 'mkv -';
  my $i = 0;
  my $cpu_prev = 0;
  my $real_prev = 0;

  for ( @{$self->{cls}} ) { #main loop
    my $cmd_line = "$decode 2>vid_dec_$i.log | ";
    $cmd_line .= "$self->{cl_base} @{ $_ } -o enc.video_$i.$suf 2>vid_enc_$i.log";
    
    print LOG "\n\n$cmd_line\n";
    my $t0 = Benchmark->new;
    system ("$cmd_line");
    my $t1 = Benchmark->new;

    my ($real, $cpu) = $self->_real_cpu_times($t0, $t1);

    #for 2 pass, only output every other run of codec
    if ( !$self->{two_pass} or $i%2 ) {
      print "$i, ";
      $self->_print_range_vars($cmd_line, @range_vars);
      if ( $self->{two_pass} ) {
        print "${\($cpu + $cpu_prev)}, ${\($real + $real_prev)}, ";
      }
      else {
        print "$cpu, $real, ";
      }
      my ($frames, $br, $psnr) = $self->_frames_bitrate_psnr("vid_enc_$i.log");
      print "$frames, $br, $psnr\n";
    }

    printf LOG "i: $i\n";
    printf LOG "cpu: %-10.3f\t cpu_prev: %-10.3f\n", $cpu, $cpu_prev;
    printf LOG "real %-10.3f\t real_prev %-10.3f\n", $real, $real_prev;
    $cpu_prev = $cpu;
    $real_prev = $real;
    $i++;
  }

  return $self;
}


#internal methods

sub _init
{
  my $self = shift;

  #create array of command lines from $self->{settings}, store in $self
  my %settings = @{$self->{settings}};
  my ($cl_base, %ranges, @cls_to_run);

  #encoder name, handle it separately
  $cl_base .= delete ${settings{'--encoder'}};
  $self->{encoder} = $cl_base;

  #common part of all command lines
  while ( my ($key, $val) = each %settings ) {
    if ( ref($val) ) {
      $ranges{$key} = $val; #save this setting for cross product combinations
    }
    elsif ( defined($val) ) {
      $cl_base .= " $key=$val";
    }
    else {
      $cl_base .= " $key";
    }
  }

  #combinatorial part
  my @ranges_arr = map {
    my $k = $_;
    [ map "$k=$_", @{$ranges{$k}} ];
  }
  keys %ranges;

  push @cls_to_run, $_ for _cross_product(@ranges_arr);

  $self->{cls} = \@cls_to_run;
  $self->{ranges} = \%ranges;
  $self->{cl_base} = $cl_base;

  #check for 2 pass
  $self->_two_pass();
  
  return $self;
}

sub _cross_product {
  my @input = @_;
  my @ret = map [$_], @{ shift @input };

  for my $a2 (@input) {
    @ret = map {
      my $v = $_;
      map [@$v, $_], @$a2;
    }
    @ret;
  }
  return @ret;
}

sub _two_pass {
  my $self = shift;
  my %settings = @{$self->{settings}};

  unless ( exists $settings{'--target-bitrate'} or exists $settings{'--bitrate'} ) {
    return;
  }

  #add 1 pass and 2 pass command lines for each
  #command line and put them in the cls array,
  #replacing what is currently there
  my (@temp_cls, $br);
  $self->{two_pass} = 1;

  for ( @{$self->{cls}} ) {
    if ( $self->{encoder} eq "vpxenc" ) {
      $self->{cl_base} =~ s/--passes=\d //g;
      $self->{cl_base} =~ s/--pass=\d //g;
      #todo: for first pass, use lag-in-frames=0 ?
      $br = $settings{'--target-bitrate'};
      push @temp_cls, [ "--minsection-pct=10 --maxsection-pct=800 --fpf=vpx_2pass.log --target-bitrate=$br --passes=2 --pass=1 @{$_} " ];
      push @temp_cls, [ "--minsection-pct=10 --maxsection-pct=800 --fpf=vpx_2pass.log --target-bitrate=$br --passes=2 --pass=2 @{$_} " ];
    }
    elsif ( $self->{encoder} eq "obe-vod" or $self->{encoder} eq "x265" ) {
      $br = $settings{'--bitrate'};
      push @temp_cls, [ "--pass=1 --stats=encoder_2pass.log --bitrate=$br @{$_} " ];
      push @temp_cls, [ "--pass=2 --stats=encoder_2pass.log --bitrate=$br @{$_} " ];
    }
    else {
      die "encoder name not recognized\n";
    }
  }

  $self->{cls} = \@temp_cls;
  return;
}

sub _print_range_vars {

  my $self = shift;
  my $cmd_line = shift;
  my @range_vars = @_;

  foreach my $var (@range_vars) {
    my ($wanted) = $cmd_line =~ /$var=(\d+|\w+)/;
    die "encodist: couldn't find $wanted $!" unless defined $wanted;
    print "$wanted, ";
  }

}

sub _real_cpu_times {
  #uses Benchmark and Time::HiRes
  my $self = shift;
  my $t0 = shift;
  my $t1 = shift;
  my ($real, $cpu);

  my $td = timediff($t1, $t0);
  my $elapsed = timestr($td, 'all');

  ($real) = $elapsed =~ /(\d+\.\d+)\s+wallclock/;
  ($cpu) = $elapsed =~ /\s+(\d+\.\d+)\s+CPU\)/;

  return ($real, $cpu);
}

sub _cpu_time {
  #obsolete, use _real_cpu_times
  my $self = shift;
  my ($user,$system,$cuser,$csystem,$cuser_diff,$csystem_diff);

  ($user,$system,$cuser,$csystem) = times;

  #$cuser_diff = $cuser - $self->{cuser_p};
  #$csystem_diff = $csystem - $self->{csystem_p};

  #print "          cuser: $cuser\n";
  #print "        csystem: $csystem\n";
  #print "  self->cuser_p: $self->{cuser_p}\n";
  #print "self->csystem_p: $self->{csystem_p}\n";
  #print "        cuser_d: $cuser_diff\n";
  #print "      csystem_d: $csystem_diff\n";
  #print "                 ${\($cuser_diff + $csystem_diff)}\n";

  #$self->{cuser_p} = $cuser;
  #$self->{csystem_p} = $csystem;

  return $cuser_diff + $csystem_diff;
}

sub _frames_bitrate_psnr {
  my $self = shift;
  my $logfile = shift;
  my ($frames, $br, $psnr);

  #get frames, bitrate, psnr from encoder log
  if ( $self->{encoder} eq "vpxenc" ) {
    my $res = readpipe "tail -2 $logfile";
    ($frames) = $res =~ /Pass.*frame\s+(\d+)\//;
    ($br) = $res =~ / (\w+)b\/s/;
    ($psnr) = $res =~ /U\/V\)\s+(\d+\.\d+)/;
    $br /= 1000;
  }
  elsif ( $self->{encoder} eq "obe-vod" ) {
    my $res = readpipe "tail -3 $logfile";
    ($frames) = $res =~ /encoded\s+(\d+)\s+frames/;
    ($br) = $res =~ /(\d+\.\d+) kb\/s$/;
    ($psnr) = $res =~ / Global:(\d+\.\d+)/;
  }
  elsif ( $self->{encoder} eq "x265" ) {
    my $res = readpipe "tail -1 $logfile";
    ($frames) = $res =~ /encoded\s+(\d+)\s+frames/;
    ($br) = $res =~ /(\d+\.\d+) kb\/s/;
    ($psnr) = $res =~ /PSNR:\s+(\d+\.\d+)/;
  }
  else {
    die "encoder name not recognized\n";
  }

  return ($frames, $br, $psnr);
}

1;



