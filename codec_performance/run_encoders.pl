#!/usr/bin/perl -w

use Encodist;
use strict;

#for vp9, if target-bitrate is given, '--passes' and '--pass' are taken
#care of automatically. whatever values are put in the hash will be ignored.
#if target-bitrate is not given, '--passes' => 1, '--pass' => 1, must be in the hash
#if not, it will not run correctly
my %vp9 = (
'--encoder' => 'vpxenc',
'--codec' => 'vp9',
'--lag-in-frames' => [ 16, 25 ],
'--cpu-used' => [ 4, 8 ],
'--threads' => 8,
'--target-bitrate' => '4000',
'--passes' => 1,
'--pass' => 1,
'--i420' => undef,
'--verbose' => undef,
'--end-usage' => 'q',
'--cq-level' => 42,
'--min-q' => 4,
'--max-q' => 52,
'--disable-warning-prompt' => undef,
'--bit-depth' => 8,
'--input-bit-depth' => 8,
'--good' => undef, 
'--psnr' => undef, 
'--sharpness' => 0,
'--noise-sensitivity' => 0,
'--error-resilient' => 0,
'--auto-alt-ref' => 1,
'--static-thresh' => 0,
'--fps' => '24/1',
'--profile' => 0,
'--tile-columns' => 6,
'--frame-parallel' => 1,
'--kf-min-dist' => 0,
'--width' => 3840,
'--height' => 1714
#'--tune' => 'psnr',
);

my %h264 = (
'--encoder' => 'obe-vod',
'--level' => '5.1',
'--threads' =>  [ 8, 12 ],
'--bitrate' => 8000,
'--demuxer' =>  'y4m',
'--preset' =>  'faster',
'--input-depth' =>  8,
'--ref' =>  3,
'--bframes' =>  0,
'--crf' =>  24,
'--fps' =>  '24/1',
'--input-res' =>  '3840x1714',
'--sar' =>  '1:1',
'--no-interlaced' => undef,
'--stitchable' => undef,
'--psnr' => undef,
'--profile' => 'baseline',
'--level' => '5.1',
'--output-csp' => 'i420'
);


my %hevc = (
'--encoder' => 'x265',
'--frame-threads' => [ 6, 8],
'--input' => '-',
'--bitrate' => 4000,
'--y4m' => undef,
'--input-res' => '3840x1714',
'--log-level' => 'info',
'--preset' => 'fast',
'--crf' => 24,
'--wpp' => undef,
'--fps' => '24.0',
'--no-interlace' => undef,
'--profile' => 'main',
'--level-idc' =>  0,
'--input-depth' => 8,
'--output-depth' => 8,
'--no-open-gop' => undef,
'--bframes' => 4,
'--b-adapt' => 2,
'--ref' => 3,
'--sar' => '1:1',
'--psnr' => undef
);

my %dec = (
'-threads' => 4,
'-t' => '10.00',
#'-ss' => '210.00',
);

my $infile = '/mnt/hgfs/work/sources/tearsofsteel_4k.mov';
#my $infile = 'tearsofsteel_4k.mov';

my $enc_264 = Encodist->new(%h264);
$enc_264->set_input_file($infile);
$enc_264->set_decode_settings(%dec);
$enc_264->set_output_name('out_264');
$enc_264->run();

my $enc_vp9 = Encodist->new(%vp9);
$enc_vp9->set_input_file($infile);
$enc_vp9->set_decode_settings(%dec);
$enc_vp9->set_output_name('out_vp9');
$enc_vp9->run();

my $enc_hevc = Encodist->new(%hevc);
$enc_hevc->set_input_file($infile);
$enc_hevc->set_decode_settings(%dec);
$enc_hevc->set_output_name('out_hevc');
$enc_hevc->run();






