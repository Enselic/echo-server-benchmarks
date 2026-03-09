if (exists("outputfile")) {
    set term pngcairo size 1400,800 noenhanced
    set output outputfile
} else {
    set term qt size 1400,800 noenhanced
}

set datafile separator "\t"

set title exists("title") ? title : "Latency Histogram"
set xlabel "Latency (ms)"
set ylabel "Requests"
set grid
set key off

# Fixed histogram bucket width requested by benchmark configuration.
binwidth = 10.0
bin(x, w) = w * floor(x / w)

plot datafile using (bin($1, binwidth)):(1.0) smooth freq with boxes fc rgb "#3b82f6" lc rgb "#1f2937"

if (!exists("outputfile")) {
    pause -1
}
