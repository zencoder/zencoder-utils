### Encodist

Encodist is a perl module and a sample program that runs encoding jobs, measures run times, captures various output metrics and generates plots.

**Encodist.pm**

> Perl module

**run\_encoders.pl**
  
> sample program

**plotting/**

> directory of .gp files which can be used with gnuplot.
> TODO: automate creating these and running gnuplot with them

#### Installation

TBD

#### Running

TBD

If no output name is provided, Encodist
uses the default "out_*" for the names
of the output directories, incremented by job number.
If you create multiple Encodist objects provide an output name, otherwise
the "_out_*" will be overwritten.


