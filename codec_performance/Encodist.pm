#!/usr/bin/perl

package Encodist;
use strict;
use warnings;

my $jn;

sub new {
  my $class = shift; # $_[0] contains the class name
  my @com = @_;
  my $self = {};

  bless $self, $class;

  $self->{name} = $class;
  $self->{settings} = \@com;
  $self->_init();

  return $self;
}

sub set_input_file {
  my $self = shift;
  my $infile = shift;

  die "input file not found: $infile\n" unless (-f $infile);
  $self->{infile} = $infile;

  #replace tmpinfile
  $self->{decode} =~ s/tmpinfile/$infile/ if exists $self->{decode};

  return $self;
}

sub set_output_name {
  my $self = shift;
  my $outname = shift;

  open (OUT, ">$outname.csv") or die "can't open output file: $outname.csv\n";
  select OUT;
  
  $self->{outname} = $outname;

  return $self;
}

sub set_decode_settings {
  my $self = shift;
  my $dec_options = join(' ', @_);

  $self->{decode} = "ffmpeg -loglevel verbose -y " . $dec_options;
  my $tmpfile = $self->{infile} || 'tmpinfile';
  $self->{decode} .= " -i $tmpfile -f yuv4mpegpipe -";

  #optional
  #$self->{decode} .= "-r 24/1 -an -map 0:0 -pix_fmt yuv420p ";
  #$self->{decode} .= "-sws_flags lanczos -vf [in]scale=3840:1714,setsar=sar=1/1[processed] ";

  return $self;
}

sub run {
  #overview: run process() for each Processor object in the grid
  #get the results from each object and write to csv
  my $self = shift;

  #verify input
  die "no input file given\n" unless defined $self->{infile};

  #verify decoding settings
  if ( !defined $self->{decode} ) { #nothing provided, lets set some defaults
    my %dec_settings = ('-threads' => 4, '-t' => '15.00', '-ss' => '10.00');
    $self->set_decode_settings(%dec_settings);
  }

  my @enc = ($self->{encoder}, $self->{decode}, $self->{outname}, $self->{aws});
  my @metrics = qw/br frames psnr real cpu outfile_sz ext_psnr ext_ssim/;

  for my $proc ( @{$self->{grid}} ) {
    $proc->process(@enc);
    my %job = $proc->results('job_number', 'cmd_extra', @metrics);
    my $n = $job{'job_number'};

    if ( $n == 0 )  { #print the heading
      print "#n, ";
      print /--(\S+)=/, ", " for @{$job{'cmd_extra'}};
      print "$_, " for @metrics; 
    }

    print "\n$n, ";
    print /--\S+=(\d+|\w+)/, ", " for @{$job{'cmd_extra'}}; #NOTE: no dashes allowed in $val
    print "$job{$_}, " for @metrics;
  }

  print "\n";

  return $self;
}


#internal methods

sub _init {
  my $self = shift;
  my @grid;
   
  #create array of command lines from $self->{settings}
  my %settings = @{$self->{settings}};
  my ($cl_base, %ranges);

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

  #create the processors and put them all in the grid
  $jn = 0;
  push @grid, Processor->new($_) for _cross_product(@ranges_arr);
  $_->{cmd} = $cl_base for @grid;

  #get aws machine instance type
  $self->{aws} = `wget -q -O - http://instance-data/latest/meta-data/instance-type`;
  
  $self->{grid} = \@grid;

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


package Processor;
use strict;
use warnings;
use Time::HiRes;
use Benchmark ':hireswallclock';

sub new {
  my $class = shift;
  my $cmd_ex = shift;
  my $self = {
    encoder => '',         #codec name
    decoder => '',         #decoder and options
    cmd => '',             #base command line
    cmd_extra => '',       #cmd line options ranges
    multipass_cmds => '',  #if bitrate is given
    job_number => -1,
    #results:
    outdir => '',          #output directory name
    real => 0,             #wallclock time
    cpu => 0,              #cpu time (user + system)
    frames => 0,           #number of frames processed
    br => 0,               #bitrate in Kbps
    psnr => 0,
    ssim => 0,
    outfile_sz => 0,       #size in bytes of output video
    ext_psnr => 0,
    ext_ssim => 0,
  };

  bless $self, $class;

  #$self->{cmd_extra} = join ' ', @$cmd_ex;
  $self->{cmd_extra} = $cmd_ex;
  $self->{job_number} = $jn++;



  return $self;
}

sub process {
  my $self = shift;
  $self->{encoder} = shift;
  $self->{decoder} = shift;
  my $outname = shift || "_out";
  my $aws = shift || "unkown";

  my $j = $self->{job_number};
  my $outdir = "$outname"."_$j";
  $self->{outdir} = $outdir;
  mkdir $outdir;

  #Log file
  open (LOG, ">$outdir/encodist.log") or die "can't open log file: $outdir/encodist.log\n";  

  my $suf = $self->{encoder} eq 'x265' ? 'hevc' : 'mkv -';

  print LOG "    aws: $aws\n";
  print LOG "$j  @{$self->{cmd_extra}}\n";
  print LOG "outname: $outname      outdir: $outdir\n";
  print LOG "decoder: $self->{decoder}\n";
  print LOG "encoder: $self->{encoder}   $suf\n";

  if ( $self->_multipass ) {
    my ($real_step, $cpu_step) = 0;
    print LOG "***2pass***:\n";
    foreach ( @{$self->{multipass_cmds}} ) {
      print LOG "\n$_\n";

      my $t0 = Benchmark->new;
      system ($_);
      my $t1 = Benchmark->new;

      ($real_step, $cpu_step) = $self->_real_cpu_times($t0, $t1);

      print LOG "      real: $real_step    cpu: $cpu_step\n";
      $self->{real} += $real_step;
      $self->{cpu} += $cpu_step;
    }
    print LOG "total real: $self->{real}    cpu: $self->{cpu}\n";
  }
  else {
    my $cmd_line = "$self->{decoder} 2>$outdir/vid_dec.log | ";
    $cmd_line .= "$self->{cmd} @{$self->{cmd_extra}} -o $outdir/enc.video.$suf 2>$outdir/vid_enc.log";
    print LOG "$cmd_line\n";

    my $t0 = Benchmark->new;
    system ($cmd_line);
    my $t1 = Benchmark->new;

    ($self->{real}, $self->{cpu}) = $self->_real_cpu_times($t0, $t1);
    print LOG "      real: $self->{real}    cpu: $self->{cpu}\n";
  }

  ($self->{frames}, $self->{br}, $self->{psnr}) = $self->_frames_bitrate_psnr("$outdir/vid_enc.log");
  $suf =~ s/ -//;
  $self->{outfile_sz} = -s "$outdir/enc.video.$suf";

  ($self->{ext_psnr}, $self->{ext_ssim}) = $self->_external_psnr_ssim;
  print LOG " ext_psnr: $self->{ext_psnr}   ext_ssim: $self->{ext_ssim}\n";

  return $self;
}

sub reveal {
  my $self = shift;
  print "$self->{job_number}\t$self->{decoder}\n";
  print "$self->{cmd}\n";
  print "@{$self->{cmd_extra}}\n\n";
}

sub results {

  my $self = shift;
  my @wanted = @_;

  my %res_hash;
  $res_hash{$_} = $self->{$_} for @wanted;
  return %res_hash;
}

sub _multipass {
  my $self = shift;

  #a bitrate setting implies multipass
  return 0 unless ( $self->{cmd} =~ /bitrate/ );

  my (@passes, @cmds);

  my $suf = $self->{encoder} eq 'x265' ? 'hevc' : 'mkv -';
  my $out = $self->{outdir};

  if ( $self->{encoder} eq "vpxenc" ) {
    $self->{cmd} =~ s/--passes=\d //g;
    $self->{cmd} =~ s/--pass=\d //g;
    #TODO: for first pass, use lag-in-frames=0 ?
    push @passes, "--minsection-pct=10 --maxsection-pct=800 --fpf=$out/vpx_2pass.log --passes=2 --pass=1 ";
    push @passes, "--minsection-pct=10 --maxsection-pct=800 --fpf=$out/vpx_2pass.log --passes=2 --pass=2 ";

  }
  elsif ( $self->{encoder} eq "x264" or $self->{encoder} eq "obe-vod" or $self->{encoder} eq "x265" ) {
    push @passes, "--pass=1 --stats=$out/encoder_2pass.log ";
    push @passes, "--pass=2 --stats=$out/encoder_2pass.log ";
  }
  else {
    die "encoder name not recognized\n";
  }

  for (@passes) {
    my $cmdline = "$self->{decoder} 2>$out/vid_dec.log | ";
    $cmdline .= "$self->{cmd} @{$self->{cmd_extra}} $_ -o $out/enc.video.$suf 2>$out/vid_enc.log";
    push @cmds, $cmdline;
  }

  $self->{multipass_cmds} = \@cmds;

  return 1;
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
  elsif ( $self->{encoder} eq "obe-vod" or $self->{encoder} eq "x264" ) {
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

sub _external_psnr_ssim {

  #local ffmpeg is required at this time
  return (0, 0) unless (-f "ffmpeg/ffmpeg");

  my $self = shift;
  my $ffmp = "ffmpeg/ffmpeg";

  my ($infile) = $self->{decoder} =~ / -i (\S+) /;
  my ($insuf) = $infile =~ /\w+\.(\w+)/;
  my ($fps) = $self->{cmd} =~ / --fps=(\d+)\/1 /;

  #first, need a reference file "trunc" with the same number of frames as the output
  my $trunc = "$self->{outdir}/trunc.$insuf";
  my $stats_out = "$self->{outdir}/ffmpeg_stats.out";

  my $codeccopy = "";
  $codeccopy = " -c:v copy " if ($insuf ne "y4m");
  my $truncate = "$ffmp -y -i $infile $codeccopy -vframes $self->{frames} $trunc";
  system($truncate);

  #run local ffmpeg and write results to file
  my $suf = $self->{encoder} eq 'x265' ? 'hevc' : 'mkv';
  my $compute = "$ffmp -y -r $fps -i $self->{outdir}/enc.video.$suf -i $trunc -lavfi \"ssim;[0:v][1:v]psnr\" -f null - >$stats_out 2>&1";
  system($compute);

  #extract ssim, psnr from ffmpeg output
  my $res = readpipe "tail -2 $stats_out";

  my ($ssim) = $res =~ /SSIM.*All:(\d+\.\d+)/;
  my ($psnr) = $res =~ /PSNR.*average:(\d+\.\d+)/;

  unlink $trunc;
  return ($psnr, $ssim);
}

1;



