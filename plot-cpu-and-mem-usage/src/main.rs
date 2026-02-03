use std::fs;
use std::ops::Sub;
use std::thread;
use std::time::{Duration, Instant};

const INTERVAL_SECS: f64 = 1.0; // seconds between samples
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

impl Sub for CpuTimes {
    type Output = CpuTimes;

    fn sub(self, rhs: CpuTimes) -> Self::Output {
        CpuTimes {
            user: self.user.strict_sub(rhs.user),
            nice: self.nice.strict_sub(rhs.nice),
            system: self.system.strict_sub(rhs.system),
            idle: self.idle.strict_sub(rhs.idle),
            iowait: self.iowait.strict_sub(rhs.iowait),
            irq: self.irq.strict_sub(rhs.irq),
            softirq: self.softirq.strict_sub(rhs.softirq),
            steal: self.steal.strict_sub(rhs.steal),
            guest: self.guest.strict_sub(rhs.guest),
            guest_nice: self.guest_nice.strict_sub(rhs.guest_nice),
        }
    }
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
    let start_time = std::time::SystemTime::now();
    let mut prev = read_cpu_times_once();
    loop {
        std::thread::sleep(Duration::from_secs(1));
        let current = read_cpu_times_once();
        
        // TODO: According to docs iowait can decrease
        let delta = current - prev;
        let total = delta.user
        + delta.nice
        + delta.system
        + delta.idle
        + delta.iowait
        + delta.irq
        + delta.softirq
        + delta.steal
        + delta.guest
        + delta.guest_nice;
        let idle_equiv = delta.idle + delta.iowait + delta.guest + delta.guest_nice;
        let usage = total - idle_equiv;
        let usage_percentage = (usage as f64 / total as f64) * 100.0;

        let elapsed = start_time.elapsed().unwrap().as_secs_f64();
        let mem_available = get_mem_available().unwrap_or(0);
        println!("{elapsed:.2}	{usage_percentage:.2}	{mem_available}");

        prev = current;
    }
}


fn get_mem_available() -> Option<u64> {
    let file = File::open("/proc/meminfo").ok()?;
    let reader = BufReader::new(file);

    for line in reader.lines().flatten() {
        if line.starts_with("MemAvailable:") {
            return line
                .split_whitespace()
                .nth(1)?
                .parse::<u64>()
                .ok();
        }
    }
    None
}