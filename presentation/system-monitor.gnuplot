if (exists("outputfile")) {
     set term pngcairo size 1400,800 noenhanced
     set output outputfile
} else {
     set term qt size 1400,800 noenhanced
}
set datafile separator "\t"
set decimalsign ","

set title "CPU% and MemAvailable MB"
set xlabel "seconds"

set grid
set key top center horizontal
set tics nomirror

set ylabel "CPU%"
set y2label "MemAvailable MB"
set y2tics

# Fix MemAvailable MB to the requested range.
if (!exists("min_avail_kb")) min_avail_kb = 50000
if (!exists("max_avail_kb")) max_avail_kb = 100000
set y2range [min_avail_kb/1000.0:max_avail_kb/1000.0]

# Fix CPU to percent scale.
set yrange [0:100]

# datafile must be passed via -e "datafile='...'"
plot datafile using 1:2 with lines lw 2 title "CPU%", \
     ''       using 1:($3/1000.0) axes x1y2 with lines lw 2 title "MemAvailable MB"

if (!exists("outputfile")) {
     pause -1
}
