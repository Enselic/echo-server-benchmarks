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
max_latency = 100.0
# if (!exists("max_latency")) {
#     stats datafile using 1 nooutput
#     if (STATS_records > 0) {
#         max_latency = (STATS_max > int(STATS_max)) ? (int(STATS_max) + 1.0) : STATS_max
#     } else {
#         max_latency = 1.0
#     }
# }
set xrange [0:max_latency]
set grid
set key off

# Fixed histogram bucket width requested by benchmark configuration.
binwidth = 1.0
bin(x, w) = w * floor((x >= max_latency ? (max_latency - 1e-9) : x) / w)

# Compute percentiles from the first column of the input data.
percentile(p) = real(word(system(sprintf("sort -n -k1,1 '%s' | awk 'BEGIN{pct=%f} {v[NR]=$1} END{if(NR==0){print \"NaN\"; exit} idx=int((NR-1)*pct+1); if(idx<1) idx=1; if(idx>NR) idx=NR; print v[idx]}'", datafile, p)), 1))

p50 = percentile(0.5)
p90 = percentile(0.9)
p99 = percentile(0.99)
p999 = percentile(0.999)

set style line 101 lc rgb "#ef4444" lw 2 dt 2

if (p50 == p50) {
    set arrow 50 from p50, graph 0 to p50, graph 1 nohead ls 101
    set label 50 sprintf("p50 %.2f ms", p50) at p50, graph 0.98 rotate by 90 right tc rgb "#ef4444"
}
if (p90 == p90) {
    set arrow 90 from p90, graph 0 to p90, graph 1 nohead ls 101
    set label 90 sprintf("p90 %.2f ms", p90) at p90, graph 0.98 rotate by 90 right tc rgb "#ef4444"
}
if (p99 == p99) {
    set arrow 99 from p99, graph 0 to p99, graph 1 nohead ls 101
    set label 99 sprintf("p99 %.2f ms", p99) at p99, graph 0.98 rotate by 90 right tc rgb "#ef4444"
}
if (p999 == p999) {
    set arrow 999 from p999, graph 0 to p999, graph 1 nohead ls 101
    set label 999 sprintf("p999 %.2f ms", p999) at p999, graph 0.98 rotate by 90 right tc rgb "#ef4444"
}

plot datafile using (bin($1, binwidth)):(1.0) smooth freq with boxes fc rgb "#3b82f6" lc rgb "#1f2937"

if (!exists("outputfile")) {
    pause -1
}
