set terminal png nocrop enhanced size 1020,580 font "verdana,10" 
set output 'vp9_wallclock.png'
set datafile separator ","

set xrange  [ 7.5 : 14.5 ]
set yrange  [ 100 : 1200 ]
set y2range  [ 39.5 : 42 ]

set ylabel "real"
set y2label "psnr"

set xtics
set ytics nomirror
set y2tics

#set multiplot layout 1,2
set bmargin 3.5
set grid ytics

#####################################################
#unset key
set key maxrows 4
set title "wallclock time"
set xlabel "lag-in-frames"

plot 'csv_wallclock.dat' every 4::0::28 using 2:5:xtic(2) with linespoints lw 2 lt 8 lc rgb "#0077CC" title "cpu-used = 2" axes x1y1, \
                       '' every 4::1::28 using 2:5:xtic(2) with linespoints lw 2 lt 7 title "cpu-used = 3" axes x1y1, \
                       '' every 4::2::28 using 2:5:xtic(2) with linespoints lw 2 lt 9 title "cpu-used = 4" axes x1y1, \
                       '' every 4::3::28 using 2:5:xtic(2) with linespoints lw 2 lt 2 title "cpu-used = 5" axes x1y1, \
                       '' every 4::0::28 using 2:8:xtic(2) with linespoints lw 1 lt 8 lc rgb "#0077CC" title "psnr cpu-used=2" axes x1y2, \
                       '' every 4::1::28 using 2:8:xtic(2) with linespoints lw 1 lt 7 title "psnr cpu-used=3" axes x1y2, \
                       '' every 4::2::28 using 2:8:xtic(2) with linespoints lw 1 lt 9 title "psnr cpu-used=4" axes x1y2, \
                       '' every 4::3::28 using 2:8:xtic(2) with linespoints lw 1 lt 2 title "psnr cpu-used=5" axes x1y2



#below places a string with the data value at the point in the plot (for debugging):
#                       '' every 12::0::24 using 2:5:5 with labels center offset 0,1 notitle, \
#                       '' every 12::3::27 using 2:5:5 with labels center offset 0,1 notitle, \
#                       '' every 12::6::30 using 2:5:5 with labels center offset 0,1 notitle, \
#                       '' every 12::9::33 using 2:5:5 with labels center offset 0,1 notitle


#####################################################
#set key
#unset ylabel
#set ytics format ''
#set title "real"
#set xlabel "lag-in-frames"

#plot 'csv_wallclock.dat' every 12::2::204 using 2:5:xtic(2) with linespoints lw 2 lt 8 lc rgb "#0077CC" title "cpu-used = 1", \
#                       '' every 12::5::204 using 2:5:xtic(2) with linespoints lw 2 lt 7 title "cpu-used = 2", \
#                       '' every 12::8::204 using 2:5:xtic(2) with linespoints lw 2 lt 9 title "cpu-used = 3", \
#                       '' every 12::11::204 using 2:5:xtic(2) with linespoints lw 2 lt 2 title "cpu-used = 4"

#unset multiplot

