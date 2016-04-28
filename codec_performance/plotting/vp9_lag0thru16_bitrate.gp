set terminal png nocrop enhanced size 1520,580 font "verdana,10" 
set output 'vp9_lag0thru16_bitrate.png'
set datafile separator ","

set xrange  [ -0.5 : 16.5 ]
set yrange  [ 3500: 4750 ]

set ylabel "Kbps"

set xtics
set ytics

set multiplot layout 1,2
set bmargin 3.5
set grid ytics

#####################################################
unset key
set title "Bitrate threads 4"
set xlabel "lag-in-frames"

plot 'vp9_lag0thru16.dat' every 12::0::204 using 2:7:xtic(2) with linespoints lw 2 lt 8 lc rgb "#0077CC" title "cpu-used=1", \
                       '' every 12::3::204 using 2:7:xtic(2) with linespoints lw 2 lt 7 title "cpu-used=2", \
                       '' every 12::6::204 using 2:7:xtic(2) with linespoints lw 2 lt 9 title "cpu-used=3", \
                       '' every 12::9::204 using 2:7:xtic(2) with linespoints lw 2 lt 2 title "cpu-used=4", \
#                       '' every 12::0::131 using 2:8:8 with labels center offset 0,1 notitle, \
#                       '' every 12::3::131 using 2:8:8 with labels center offset 0,1 notitle, \
#                       '' every 12::6::131 using 2:8:8 with labels center offset 0,1 notitle, \
#                       '' every 12::9::131 using 2:8:8 with labels center offset 0,1 notitle
#

#below places a string with the data value at the point in the plot (for debugging):

#plot 'vp9_lag0thru16.dat' every 12::0::24 using 2:5:xtic(2) with linespoints lw 2 lt 8 lc rgb "#0077CC" title "cpu-used = 1", \
#                       '' every 12::0::24 using 2:5:5 with labels center offset 0,1 notitle, \
#                       '' every 12::3::27 using 2:5:xtic(2) with linespoints lw 2 lt 7 title "cpu-used = 2", \
#                       '' every 12::3::27 using 2:5:5 with labels center offset 0,1 notitle, \
#                       '' every 12::6::30 using 2:5:xtic(2) with linespoints lw 2 lt 9 title "cpu-used = 3", \
#                       '' every 12::6::30 using 2:5:5 with labels center offset 0,1 notitle, \
#                       '' every 12::9::33 using 2:5:xtic(2) with linespoints lw 2 lt 2 title "cpu-used = 4", \
#                       '' every 12::9::33 using 2:5:5 with labels center offset 0,1 notitle


#####################################################
set key
unset ylabel
set ytics format ''
set title "Bitrate threads 8"
set xlabel "lag-in-frames"

plot 'vp9_lag0thru16.dat' every 12::2::204 using 2:7:xtic(2) with linespoints lw 2 lt 8 lc rgb "#0077CC" title "cpu-used=1", \
                       '' every 12::5::204 using 2:7:xtic(2) with linespoints lw 2 lt 7 title "cpu-used=2", \
                       '' every 12::8::204 using 2:7:xtic(2) with linespoints lw 2 lt 9 title "cpu-used=3", \
                       '' every 12::11::204 using 2:7:xtic(2) with linespoints lw 2 lt 2 title "cpu-used=4", \
#                       '' every 12::2::131 using 2:8:8 with labels center offset 0,1 notitle, \
#                       '' every 12::5::131 using 2:8:8 with labels center offset 0,1 notitle, \
#                       '' every 12::8::131 using 2:8:8 with labels center offset 0,1 notitle, \
#                       '' every 12::11::131 using 2:8:8 with labels center offset 0,1 notitle


unset multiplot

