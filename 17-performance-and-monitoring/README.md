# 17. Performance and Monitoring

"The server is slow" is not a diagnosis. Slowness comes from one of four resources: **CPU**, **memory**, **disk I/O**, or **network**, or from an application waiting on something else. This chapter gives you a fixed routine to find which one, in a few minutes.

## What you will learn

- The first 60 seconds on a slow server
- Reading load average, CPU states, and memory correctly
- Finding disk I/O bottlenecks
- Out-of-memory (OOM) kills
- Collecting history with `sar`
- How cloud limits (burstable CPU, disk IOPS) show up inside Linux

## The first 60 seconds

Run these in order. Each one takes a few seconds and points to the next.

```bash
uptime                          # 1. load average trend
dmesg -T | tail -20             # 2. kernel errors, OOM kills (sudo if needed)
vmstat 1 5                      # 3. CPU, memory, swap, I/O wait, run queue
mpstat -P ALL 1 3               # 4. per-CPU usage (sysstat package)
free -h                         # 5. memory
iostat -xz 1 3                  # 6. disk utilisation and latency (sysstat package)
sar -n DEV 1 3                  # 7. network throughput (sysstat package)
top -o %CPU                     # 8. which process
```

Install the tools once:

```bash
sudo apt install -y sysstat          # Red Hat family: sudo dnf install -y sysstat
```

## Load average

```bash
uptime
```

Output (example):

```text
 12:40:01 up 3 days,  2:14,  1 user,  load average: 3.85, 2.10, 0.95
```

The three numbers are averages over 1, 5, and 15 minutes. Load counts processes that are **running or waiting** to run, including processes waiting on disk.

Compare with the number of CPUs (`nproc`):

- Load below the CPU count: the CPUs are keeping up.
- Load above the CPU count: work is queuing.
- Rising (`3.85 > 2.10 > 0.95`): the problem started recently and is getting worse.

High load with low CPU usage usually means processes waiting on disk (see I/O wait below).

## vmstat: the overview

```bash
vmstat 1 5
```

Output (example):

```text
procs -----------memory---------- ---swap-- -----io---- -system-- -------cpu-------
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st gu
 4  0      0 212340  51200 5102300    0    0     5    40  900 1500 92  6  2  0  0  0
 5  0      0 210900  51200 5102400    0    0     0    36  910 1520 94  5  1  0  0  0
```

| Column | Meaning | Warning sign |
|---|---|---|
| `r` | Processes waiting for CPU | Higher than CPU count for a long time |
| `b` | Processes blocked on I/O | Above 0 constantly |
| `si` / `so` | Swap in / out per second | Anything above 0 regularly means memory pressure |
| `us` / `sy` | CPU in user / kernel code | `us` near 100: application busy |
| `wa` | CPU idle waiting for I/O | Above ~10 to 20: disk bottleneck |
| `st` | CPU stolen by the hypervisor | Above 0 on burstable VMs: out of CPU credits or noisy host |
| `gu` | CPU running guest VMs (only on hosts that run VMs) | Ignore on cloud VMs |

The first line is an average since boot. Read the lines after it.

## CPU

```bash
top
```

The header line `%Cpu(s): 92.0 us, 6.0 sy, 0.0 ni, 2.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st` uses the same letters as `vmstat`.

Find the top CPU users outside of `top`:

```bash
ps -eo pid,user,%cpu,%mem,etime,cmd --sort=-%cpu | head -6
```

Per-process CPU over time:

```bash
pidstat -u 1 5
```

### Cloud: burstable VMs and steal time

Azure **B-series** and AWS **T-family** (t3, t4g) VMs earn CPU credits while idle and spend them when busy. When credits run out, the VM is limited to a baseline percentage. Inside Linux this looks like high `st` (steal) or a sudden slowdown with no change in the application.

Check credits in the cloud metrics: Azure "CPU Credits Remaining", AWS "CPUCreditBalance". The fix is a larger or non-burstable size, or T-unlimited on AWS.

## Memory

```bash
free -h
```

Output (example):

```text
               total        used        free      shared  buff/cache   available
Mem:           7.7Gi       5.9Gi       210Mi        12Mi       1.6Gi       1.5Gi
Swap:             0B          0B          0B
```

Read the **available** column, not `free`. Linux uses spare memory as disk cache (`buff/cache`) and gives it back when programs need it. Low `free` with healthy `available` is normal.

Top memory users:

```bash
ps -eo pid,user,rss,%mem,cmd --sort=-rss | head -6
```

`rss` is in KB.

### Out-of-memory kills

When memory runs out, the kernel's OOM killer ends a process to save the system. The process just disappears.

```bash
sudo dmesg -T | grep -iE 'out of memory|oom-kill|killed process'
sudo journalctl -k --since "1 day ago" | grep -i oom
```

Output (example):

```text
[Tue Sep 23 12:31:44 2026] Out of memory: Killed process 3120 (java) total-vm:4102040kB, anon-rss:3056120kB, ...
```

For a systemd service, `systemctl status` also shows `Result: oom-kill`.

Fixes, in order: find why the process grew (leak, too many workers, cache settings), set limits in the application, add swap as a buffer (Chapter 12), or choose a larger VM size.

Limit a service's memory so it cannot take down the whole server:

```bash
sudo systemctl set-property myapp.service MemoryMax=1G
```

## Disk I/O

```bash
iostat -xz 1 3
```

Output (example, one interval):

```text
Device   r/s    w/s   rkB/s   wkB/s  r_await w_await aqu-sz  %util
sda      2.0  450.0    16.0 58000.0     1.20   48.50  21.80  99.80
sdc      0.0    1.0     0.0     4.0     0.00    0.50   0.00   0.10
```

| Column | Meaning | Warning sign |
|---|---|---|
| `r/s`, `w/s` | Operations per second (IOPS) | Near the disk's IOPS limit |
| `rkB/s`, `wkB/s` | Throughput | Near the disk's MB/s limit |
| `r_await`, `w_await` | Average time per operation (ms) | Rising above ~10 to 20 ms for SSD |
| `aqu-sz` | Queue length | Consistently above 1 |
| `%util` | Time the device was busy | Near 100% |

Here `sda` (the OS disk) is saturated by writes. Which process is writing?

```bash
sudo pidstat -d 1 5
sudo iotop -o          # interactive, package iotop
```

### Cloud: disk limits

Cloud disks have **IOPS and throughput limits** based on disk type and size, and the **VM size** has its own limit. A small VM with a fast disk is still limited by the VM. When `%util` is near 100 and `await` rises at a steady IOPS number, you are probably at a limit. Check the cloud metrics (Azure "Data Disk IOPS Consumed Percentage", AWS "VolumeQueueLength" and EBS burst balance for gp2).

## Network

```bash
sar -n DEV 1 3                 # throughput per interface
ss -s                          # connection counts
ss -tan state time-wait | wc -l
nstat -az | grep -iE 'retrans|drop'
```

Many retransmissions or drops point to network limits or problems on the path. Cloud VM sizes also cap network bandwidth.

## Keep history with sar

A problem that happened at 03:00 is gone by the time you log in. `sysstat` can collect data every 10 minutes:

```bash
sudo systemctl enable --now sysstat
sudo sed -i 's/^ENABLED="false"/ENABLED="true"/' /etc/default/sysstat   # Ubuntu only
```

Read yesterday's CPU and memory:

```bash
sar -u -f /var/log/sysstat/sa$(date -d yesterday +%d)     # Ubuntu path
sar -r -f /var/log/sa/sa$(date -d yesterday +%d)          # Red Hat family path
```

Output (example):

```text
03:00:01 AM  CPU  %user  %nice  %system  %iowait  %steal  %idle
03:10:01 AM  all  12.40   0.00     3.10    41.20    0.00  43.30
```

41% I/O wait at 03:10: something disk-heavy runs at 03:00. Check cron jobs and timers.

## Monitoring in the cloud

Inside-the-VM tools show the present. For alerts and history across many servers, use the platform:

| Cloud | Metrics without an agent | Guest metrics and logs |
|---|---|---|
| Azure | CPU, disk, network (host level) | Azure Monitor Agent + Data Collection Rule, VM Insights |
| AWS | CPU, disk, network in CloudWatch | CloudWatch agent (memory and disk space need the agent) |
| Google Cloud | CPU, disk, network | Ops Agent |

> Memory usage and disk **space** are not visible to the hypervisor. Without the agent, cloud dashboards cannot alert on them.

## Lab: Create and find each bottleneck

Install `stress-ng` (`sudo apt install -y stress-ng`) on a lab VM, then:

1. **CPU:** `stress-ng --cpu "$(nproc)" --timeout 60s`. In another terminal run `uptime`, `vmstat 1`, `top`. Note `us` near 100 and `r` above the CPU count.
2. **Memory:** `stress-ng --vm 1 --vm-bytes 90% --timeout 60s`. Watch `free -h` and `vmstat` `si/so`. On a small VM without swap, check `dmesg` for an OOM kill.
3. **Disk:** `stress-ng --hdd 2 --timeout 60s`. Watch `iostat -xz 1` and `vmstat` `wa`. Find the process with `pidstat -d 1`.
4. For each test, write one sentence: which command showed the problem first.

## Common problems

| Symptom | Likely cause | Next command |
|---|---|---|
| High load, low CPU usage | Processes waiting on disk | `vmstat` `b`/`wa`, `iostat -xz`, `pidstat -d` |
| High `st` | Burstable VM out of credits, or busy host | Cloud CPU credit metric |
| Process disappeared | OOM kill | `dmesg -T \| grep -i oom` |
| `free` near zero | Normal cache use | Check `available` instead |
| Slow only at certain times | Scheduled job | `sar` history, `systemctl list-timers`, crontabs |

## Next

[18. cloud-init and Metadata](../18-cloud-init-and-metadata/README.md)
