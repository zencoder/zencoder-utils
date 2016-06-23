set terminal png nocrop enhanced size 960,543 font "verdana,10" 
set output 'ssim.png'
set boxwidth 0.9 absolute
set style fill solid 1.00 border lt -1
#set key inside right top vertical Right noreverse noenhanced autotitle nobox
set key inside right top vertical Right nobox
set style histogram clustered gap 3 title textcolor lt -1
set datafile missing '-'
set style data histograms
set datafile separator ","
set grid y

#set xtics border in scale 0,0 nomirror rotate by -45 autojustify #rotate x labels by 45 deg.
set title "SSIM, PSNR and real time" font ", 11"
set xtics border
set xtics norangelimit
set xtics ()
set xlabel "lag-in-frames"

#set yrange [ 43.2 : 43.8 ]
set y2range  [ 0.9595 : 0.9605 ]
 
set ytics nomirror
set y2tics
set ylabel "psnr, and secs (scaled to fit)"
set y2label "ssim"

plot 'ssim.dat' every 3::1::12 using 6:xtic(2) title "psnr" axes x1y1, \
             '' every 3::1::12 using 11:xtic(2) title "ssim" axes x1y2, \
             '' every 3::1::12 using ($7/20.5):xtic(2) title "real" axes x1y1




