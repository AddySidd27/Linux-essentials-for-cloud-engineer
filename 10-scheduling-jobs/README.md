# 10. Scheduling Jobs

Backups, log cleanup, certificate renewal, and health checks need to run on a schedule without anyone logged in. Linux gives you two tools for this: **cron**, which is simple and everywhere, and **systemd timers**, which log better and handle missed runs.

## What you will learn

- Writing cron schedules and reading existing ones
- Common cron mistakes and how to avoid them
- Creating a systemd timer
- Running a job once at a later time
- Choosing between cron and timers

## cron

Each user has a crontab. Edit yours with:

```bash
crontab -e
crontab -l        # list
```

The format is five time fields and a command:

```text
┌───────── minute (0-59)
│ ┌─────── hour (0-23)
│ │ ┌───── day of month (1-31)
│ │ │ ┌─── month (1-12)
│ │ │ │ ┌─ day of week (0-7, 0 and 7 are Sunday)
│ │ │ │ │
* * * * *  command
```

| Schedule | Meaning |
|---|---|
| `*/5 * * * *` | Every 5 minutes |
| `0 2 * * *` | Every day at 02:00 |
| `30 1 * * 0` | Sundays at 01:30 |
| `0 */6 * * *` | Every 6 hours, on the hour |
| `0 9 1 * *` | 09:00 on the first day of each month |
| `0 8-18 * * 1-5` | Every hour 08:00 to 18:00, Monday to Friday |
| `@reboot` | Once, at startup |

> Cloud VMs usually run in **UTC**. `02:00` in cron means 02:00 UTC unless you changed the timezone. Check with `timedatectl`.

### Example: a daily backup

```bash
crontab -e
```

Add:

```text
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 2 * * * /usr/local/bin/backup-www.sh >> /var/log/backup-www.log 2>&1
```

Cron rules that prevent most failures:

1. **Use full paths** for scripts and files. Cron's `PATH` is minimal.
2. **Redirect output** to a log file (`>> file 2>&1`). Otherwise you never see errors.
3. **Make the script executable** (`chmod +x`) and test it manually first.
4. `%` has a special meaning in crontab. Escape it as `\%`, for example in `date +\%F`.

### System-wide cron

| Location | Notes |
|---|---|
| `/etc/crontab` | Has an extra **user** field before the command |
| `/etc/cron.d/<file>` | Same format as `/etc/crontab`. Good for packages and automation. |
| `/etc/cron.daily/`, `cron.weekly/`, `cron.monthly/` | Drop an executable script in. No file extension on Ubuntu. |

Example `/etc/cron.d/cleanup-tmp`:

```text
# m h dom mon dow user command
15 3 * * * root find /var/tmp -type f -mtime +7 -delete
```

### Did my cron job run?

```bash
grep CRON /var/log/syslog | tail          # Ubuntu
sudo journalctl -u cron --since today     # Ubuntu (service is cron)
sudo journalctl -u crond --since today    # Red Hat family (service is crond)
```

Output (example):

```text
Sep 23 02:00:01 web01 CRON[4123]: (azureuser) CMD (/usr/local/bin/backup-www.sh >> /var/log/backup-www.log 2>&1)
```

This proves cron started the job. Whether the job **succeeded** is in your log file.

## systemd timers

A timer is two units: a `.service` that does the work, and a `.timer` that says when.

Advantages over cron: output goes to the journal automatically, `Persistent=true` runs a missed job after the machine was off, and `systemctl list-timers` shows the next and last run.

**1. The service**

```bash
sudo tee /etc/systemd/system/disk-report.service > /dev/null <<'EOF'
[Unit]
Description=Write disk usage report

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'df -h > /var/tmp/disk-report.txt'
EOF
```

**2. The timer**

```bash
sudo tee /etc/systemd/system/disk-report.timer > /dev/null <<'EOF'
[Unit]
Description=Run disk-report every 15 minutes

[Timer]
OnCalendar=*:0/15
Persistent=true
RandomizedDelaySec=60

[Install]
WantedBy=timers.target
EOF
```

**3. Enable the timer (not the service)**

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now disk-report.timer
systemctl list-timers disk-report.timer
```

Output (example):

```text
NEXT                        LEFT     LAST PASSED UNIT              ACTIVATES
Tue 2026-09-23 11:15:23 UTC 8min left -   -      disk-report.timer disk-report.service
```

Run the job now to test it, and see its output:

```bash
sudo systemctl start disk-report.service
cat /var/tmp/disk-report.txt
journalctl -u disk-report.service -n 5 --no-pager
```

### OnCalendar examples

| Value | Meaning |
|---|---|
| `hourly`, `daily`, `weekly` | Shortcuts |
| `*-*-* 02:00:00` | Every day at 02:00 |
| `Mon..Fri 08:30` | Weekdays at 08:30 |
| `*:0/15` | Every 15 minutes |
| `Sun *-*-* 01:30:00` | Sundays at 01:30 |

Check your expression before using it:

```bash
systemd-analyze calendar "Mon..Fri 08:30"
```

Output (example):

```text
  Original form: Mon..Fri 08:30
Normalized form: Mon..Fri *-*-* 08:30:00
    Next elapse: Wed 2026-09-24 08:30:00 UTC
```

## Run something once, later

```bash
sudo apt install -y at            # Red Hat family: sudo dnf install -y at
sudo systemctl enable --now atd
echo "systemctl restart nginx" | sudo at 23:00     # the job runs as root
sudo atq                          # list pending jobs
sudo atrm 3                       # remove job 3
```

Or with systemd, no extra package:

```bash
sudo systemd-run --on-calendar="2026-09-23 23:00" systemctl restart nginx
```

## Cron or timer?

| Use cron when | Use a timer when |
|---|---|
| The job is a one-line command | You want logs in the journal |
| You need it to work the same on any Unix | The job must run even if the server was off at the scheduled time |
| A package already ships a cron file | You want to see next and last run with one command |

## Lab: Schedule a health check

1. Create `/usr/local/bin/health.sh`:

```bash
sudo tee /usr/local/bin/health.sh > /dev/null <<'EOF'
#!/bin/bash
echo "$(date -Is) load=$(cut -d' ' -f1 /proc/loadavg) root_used=$(df --output=pcent / | tail -1 | tr -d ' ')"
EOF
sudo chmod +x /usr/local/bin/health.sh
/usr/local/bin/health.sh
```

Output (example):

```text
2026-09-23T11:02:10+00:00 load=0.08 root_used=11%
```

2. Schedule it every 5 minutes with cron, writing to `/var/tmp/health.log`.
3. Replace the cron entry with a systemd timer that does the same thing.
4. Confirm with `systemctl list-timers` and `journalctl -u health.service`.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Works by hand, not from cron | Relative paths, missing `PATH`, or environment variables. | Use full paths. Set `PATH` in the crontab. |
| No output, no errors | Output not redirected. | Add `>> /var/log/job.log 2>&1`. |
| Runs at the wrong hour | Server is in UTC. | `timedatectl`. Convert your time, or set `CRON_TZ`. |
| `date +%F` breaks the crontab line | `%` is special in cron. | Use `\%`. |
| Timer never fires | You enabled the `.service` instead of the `.timer`. | `systemctl enable --now name.timer`. |

## Next

[11. Logs](../11-logs/README.md)
