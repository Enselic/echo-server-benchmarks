if (exists("outputfile")) {
     set term pngcairo size 1400,800 noenhanced
     set output outputfile
} else {
     set term qt size 1400,800 noenhanced
}
set datafile separator "\t"
set decimalsign ","

set title "CPU% och Avail_MB"
set xlabel "ms"

set grid
set key top center horizontal
set tics nomirror

set ylabel "CPU%"
set y2label "Avail_MB"
set y2tics

# Compute memory stats first (in MB), then keep a fixed 30 MB span on y2.
stats datafile using ($3/1024.0) name "MEM" nooutput
if (exists("MEM_min") && exists("MEM_max")) {
     mem_mid = (MEM_min + MEM_max) / 2.0
     set y2range [mem_mid - 15.0:mem_mid + 15.0]
} else {
     # Fallback if data is empty/unreadable.
     set y2range [0:30]
}

# Fix CPU to percent scale.
set yrange [0:100]

# datafile must be passed via -e "datafile='...'"
plot datafile using 1:2 with lines lw 2 title "CPU%", \
     ''       using 1:($3/1024.0) axes x1y2 with lines lw 2 title "Avail_MB"

if (!exists("outputfile")) {
     pause -1
}
