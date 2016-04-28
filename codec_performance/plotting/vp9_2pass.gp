set terminal png nocrop enhanced size 1020,580 font "verdana,10" 
set output 'vp9_2pass_cpu.png'
set datafile separator ","

set xrange  [ 7.5 : 14.5 ]
set yrange  [ 1000 : 4200 ]

set ylabel "user+system"

set xtics
set ytics

set bmargin 3.5
set grid ytics

#####################################################
#set key maxrows 4
set title "cpu time"
set xlabel "lag-in-frames"

plot '2pass_2.dat' every 4::0::30 using 2:4:xtic(2) with linespoints lw 2 lt 8 lc rgb "#0077CC" title "cpu-used = 2", \
             '' every 4::1::30 using 2:4:xtic(2) with linespoints lw 2 lt 7 title "cpu-used = 3", \
             '' every 4::2::30 using 2:4:xtic(2) with linespoints lw 2 lt 9 title "cpu-used = 4", \
             '' every 4::3::30 using 2:4:xtic(2) with linespoints lw 2 lt 2 title "cpu-used = 5"




