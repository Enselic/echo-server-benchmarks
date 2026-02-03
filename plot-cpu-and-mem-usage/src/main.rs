use anyhow::{anyhow, Context, Result};
use plotters::prelude::*;
use std::fs;
use std::thread;
use std::time::{Duration, Instant};

const INTERVAL_SECS: f64 = 1.0;  // seconds between samples
const DURATION_SECS: f64 = 60.0; // total seconds to record
const OUTPUT_PNG: &str = "cpu_idle.png";

/// Field docs taken from `man proc_stat`.
#[derive(Clone, Copy, Debug)]
struct CpuTimes {
    /// (1) Time spent in user mode.
    line: u64,
    /// (2) Time spent in user mode with low priority (nice).
    user: u64,
    /// (3) Time spent in system mode.
    nice: u64,
    /// (4) Time spent in the idle task.
    system: u64,
    /// (5) Time waiting for I/O to complete.
    iowait: u64,
    /// (6) Time servicing interrupts.
    irq: u64,
    /// (7) Time servicing softirqs.
    softirq: u64,
    /// (8) Stolen time, which is the time spent in other operating systems when running in a virtualized environment
    steal: u64,
    /// (9) Time spent running a virtual CPU for guest operating systems under the control of the Linux kernel.
    guest: u64,
    /// (10) Time spent running a niced guest (virtual CPU for guest operating systems under the control of the Linux kernel).
    guest_nice: u64,
}

fn read_cpu_times_once() -> CpuTimes {
    let stat = fs::read_to_string("/proc/stat").unwrap();
    let cpu_times = stat.lines().next().unwrap();

    let mut parts = cpu_times.split_whitespace();
    let tag = parts.next().expect("bad /proc/stat line");
    assert_eq!(tag, "cpu", "first line of /proc/stat didn't start with 'cpu'");

    let nums: Vec<u64> = parts
        .map(|s| s.parse::<u64>().expect("parsing cpu fields"))
        .collect();

    CpuTimes {
        line: nums.get(0).cloned().unwrap_or(0),
        user: nums.get(1).cloned().unwrap_or(0),
        nice: nums.get(2).cloned().unwrap_or(0),
        system: nums.get(3).cloned().unwrap_or(0),
        iowait: nums.get(4).cloned().unwrap_or(0),
        irq: nums.get(5).cloned().unwrap_or(0),
        softirq: nums.get(6).cloned().unwrap_or(0),
        steal: nums.get(7).cloned().unwrap_or(0),
        guest: nums.get(8).cloned().unwrap_or(0),
        guest_nice: nums.get(9).cloned().unwrap_or(0),
    }
}

/// Reads the aggregate CPU line: "cpu  user nice system idle iowait irq softirq steal guest guest_nice"
fn read_cpu_times() -> Result<CpuTimes> {
    let data = fs::read_to_string("/proc/stat").context("reading /proc/stat")?;
    let first = data
        .lines()
        .next()
        .ok_or_else(|| anyhow!("empty /proc/stat"))?;

    let mut parts = first.split_whitespace();
    let tag = parts.next().ok_or_else(|| anyhow!("bad /proc/stat line"))?;
    if tag != "cpu" {
        return Err(anyhow!("first line of /proc/stat didn't start with 'cpu'"));
    }

    // Collect the numeric fields we have (usually 10+; we only need up to iowait)
    let nums: Vec<u64> = parts
        .map(|s| s.parse::<u64>())
        .collect::<std::result::Result<Vec<_>, _>>()
        .context("parsing cpu fields")?;

    if nums.len() < 5 {
        return Err(anyhow!("not enough cpu fields in /proc/stat"));
    }

    let user = nums[0];
    let nice = nums[1];
    let system = nums[2];
    let idle = nums[3];
    let iowait = nums[4];

    // Total is sum of all fields present on that line (kernel provides cumulative jiffies)
    let total: u64 = nums.iter().sum();

    Ok(CpuTimes {
        total,
        idle: idle + iowait,
    })
}

fn idle_percent(prev: CpuTimes, curr: CpuTimes) -> Option<f64> {
    let total_delta = curr.total.saturating_sub(prev.total);
    let idle_delta = curr.idle.saturating_sub(prev.idle);
    if total_delta == 0 {
        None
    } else {
        Some((idle_delta as f64) * 100.0 / (total_delta as f64))
    }
}

fn plot(samples: &[(f64, f64)]) -> Result<()> {
    let root = BitMapBackend::new(OUTPUT_PNG, (1200, 600)).into_drawing_area();
    root.fill(&WHITE)?;

    let x_min = samples.first().map(|(t, _)| *t).unwrap_or(0.0);
    let x_max = samples.last().map(|(t, _)| *t).unwrap_or(1.0);

    let mut chart = ChartBuilder::on(&root)
        .caption("CPU Idle % (from /proc/stat)", ("sans-serif", 28))
        .margin(20)
        .x_label_area_size(45)
        .y_label_area_size(60)
        .build_cartesian_2d(x_min..x_max, 0f64..100f64)?;

    chart
        .configure_mesh()
        .x_desc("Time (s)")
        .y_desc("Idle (%)")
        .y_labels(11)
        .draw()?;

    chart.draw_series(LineSeries::new(samples.iter().copied(), &BLUE))?;

    // Optional: draw points
    chart.draw_series(samples.iter().map(|(t, y)| {
        Circle::new((*t, *y), 2, ShapeStyle::from(&BLUE).filled())
    }))?;

    root.present()?;
    Ok(())
}

fn main() -> Result<()> {
    let interval = Duration::from_secs_f64(INTERVAL_SECS);
    let target_samples = (DURATION_SECS / INTERVAL_SECS).ceil() as usize;

    let mut prev = read_cpu_times()?;
    let start = Instant::now();

    let mut series: Vec<(f64, f64)> = Vec::with_capacity(target_samples);

    for _ in 0..target_samples {
        thread::sleep(interval);

        let curr = read_cpu_times()?;
        if let Some(idle_pct) = idle_percent(prev, curr) {
            let t = start.elapsed().as_secs_f64();
            series.push((t, idle_pct));
            println!("{:8.2}s  idle={:6.2}%", t, idle_pct);
        }
        prev = curr;
    }

    plot(&series)?;
    eprintln!("Wrote {}", OUTPUT_PNG);
    Ok(())
}
