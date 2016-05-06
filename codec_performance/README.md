### Encodist

Encodist is a perl module and sample scripts that run encoding jobs and measure run times and other output metrics.

**Encodist\.pm**: Perl module

**run\_encoders.pl**: sample program scripts that show how the use the Encodist object.

**plotting/**: Directory of example .gp files which can be used with gnuplot to plot a wide range of output values.
Automating the creation of plots is TBD.

#### Quick Start Example

Create a hash with the desired codec settings, instantiate and configure an Encodist object, and call it's run method:

    #!/usr/bin/perl -w
    use Encodist;
    use strict;
    my %h264 = (
    '--encoder' => 'obe-vod',
    '--level' => '5.1',
    '--threads' =>  [ 8, 16 ],
    '--demuxer' =>  'y4m',
    '--preset' => ['faster', 'medium'], 
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

    my %dec = ('-threads' => 4, '-t' => '60.00');
    my $infile = 'tearsofsteel_4k.mov';
    my $enc_264 = Encodist->new(%h264);
    $enc_264->set_input_file($infile);
    $enc_264->set_decode_settings(%dec);
    $enc_264->set_output_name('out_264');
    $enc_264->run();

For any settings which are given as an array [ ], each value will be tried in a separate encoding job.

In this example Encodist will use obe-vod to encode the first minute of tears of steel 4 times: 8 threads with faster preset,
16 threads with faster preset, 8 threads with medium preset and 16 threads with medium preset.

The values passed to set\_decoder\_settings() should be understandable by ffmpeg decoder.

The collected outputs will be put
in an output file `out_264.csv` and a directory `out_264` will contain the output decoder 
and encoder logs, the Encodist log, the output video file, and several other auxiliary files.

#### Installation

Step 1: On the target VM, `sudo yum install perl-Time-HiRes` is required.

Step 2: Copy the input files, Encodist.pm, and main program scripts to
the VM instance. The Encodist.pm and main program need to be in the same directory.

Step 3: (Optional) For computing ssim and psnr externally with ffmpeg, installing ffmpeg 3.0 is currently required.
This step will go away once the VM image is updated with ffmpeg 3.0. Encodist looks for an `ffmpeg` dir in its current working dir,
and if it exists uses the `ffmpeg` binary in that location (in other words, `ffmpeg/ffmpeg` relative to cwd).

NOTE: In aws, using a mounted disk, such as
/media/storage0, is highly recommended as a working directory over root "/" mount point. The root "/" file
system does not have large capacity, if it starts to fill up operations will get paged.

#### Running

The following data points are collected for each run of each codec:

  * the value of each parameter for which a range was given
  * bitrate
  * number of frames
  * self reported psnr
  * real (wallclock) time 
  * cpu (user+system) time
  * output video file size 
  * psnr measured externally with ffmpeg (if ffmpeg 3.0 is available locally)
  * ssim measured externally with ffmpeg (if ffmpeg 3.0 is available locally)
  * the aws instance type that was used

Additionally, the decoder and encoder commands, as well as the decode->encode pipe command for which the timing benchmarks were
calculated are writted to the `encodist.log` file.

If no output name is provided (set\_output\_name() is not called), Encodist will output the csv data to sdtout. This
can be redirected to a file to collect all the output from all runs together. This is discouraged since
it becomes hard to determine which results correspond to which encodist object instance in the main program.

In the case where no output name is provided, the default name for the directories is "out_*", incremented by
the encoding job number.

Another alternative is to create several Encodist objects, but only provide an output name to the first one.
This single name will be used for all runs for the csv output and the base name for the output dirs.






