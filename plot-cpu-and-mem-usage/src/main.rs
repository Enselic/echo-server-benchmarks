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
    user: u64,
    /// (2) Time spent in user mode with low priority (nice).
    nice: u64,
    /// (3) Time spent in system mode.
    system: u64,
    /// (4) Time spent in the idle task.
    idle: u64,
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
    assert_eq!(parts.next().unwrap(), "cpu");

    let mut parts = parts.map(|s| s.parse::<u64>().unwrap()).fuse();
    CpuTimes {
        user: parts.next().unwrap_or_default(),
        nice: parts.next().unwrap_or_default(),
        system: parts.next().unwrap_or_default(),
        idle: parts.next().unwrap_or_default(),
        iowait: parts.next().unwrap_or_default(),
        irq: parts.next().unwrap_or_default(),
        softirq: parts.next().unwrap_or_default(),
        steal: parts.next().unwrap_or_default(),
        guest: parts.next().unwrap_or_default(),
        guest_nice: parts.next().unwrap_or_default(),
    }
}

fn main() {
    let initial = read_cpu_times_once();
    std::thread::sleep(Duration::from_secs(1));
    let later = read_cpu_times_once();
}
