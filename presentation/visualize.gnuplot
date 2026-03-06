if (exists("outputfile")) {
     set term pngcairo size 1400,800 noenhanced
     set output outputfile
} else {
     set term qt size 1400,800 noenhanced
}
set datafile separator "\t"
set decimalsign ","

set title "CPU‰ och Avail_kB"
set xlabel "ms"

set grid
set key top center horizontal
set tics nomirror

set ylabel "CPU‰"
set y2label "Avail_kB"
set y2tics

# Ranges (adjust if you want fixed ranges like in your screenshot)
set yrange [0:*]
set y2range [*:*]

# datafile must be passed via -e "datafile='...'"
plot datafile using 1:2 with lines lw 2 title "CPU‰", \
     ''       using 1:3 axes x1y2 with lines lw 2 title "Avail_kB"

if (!exists("outputfile")) {
     pause -1
}
