if (exists("outputfile")) {
     set term pngcairo size 1400,800 noenhanced
     set output outputfile
} else {
     set term qt size 1400,800 noenhanced
}
set datafile separator "\t"
set decimalsign ","

set title "CPU% and MemAvailable MB"
set xlabel "ms"

set grid
set key top center horizontal
set tics nomirror

set ylabel "CPU%"
set y2label "MemAvailable MB"
set y2tics

# Show full MemAvailable MB range from the data.
set autoscale y2
set y2range [*:*]

# Fix CPU to percent scale.
set yrange [0:100]

# datafile must be passed via -e "datafile='...'"
plot datafile using 1:2 with lines lw 2 title "CPU%", \
     ''       using 1:($3/1000.0) axes x1y2 with lines lw 2 title "MemAvailable MB"

if (!exists("outputfile")) {
     pause -1
}
