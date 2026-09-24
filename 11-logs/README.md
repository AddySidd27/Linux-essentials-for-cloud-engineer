# 11. Logs

Logs are how a server tells you what went wrong. Before you restart anything or change configuration, read the logs. This chapter shows where logs live, how to filter them quickly, and how to stop them from filling the disk.

## What you will learn

- The two logging systems: the systemd journal and text files in `/var/log`
- Filtering the journal by service, time, priority, and boot
- Which file to check for which problem, on Ubuntu and Red Hat family
- Rotating logs with `logrotate` and limiting journal size
- Where cloud logging agents fit in

## Two places logs go

| System | Stores | Read with |
|---|---|---|
| **systemd journal** (`journald`) | Output of every systemd service, kernel messages, boot messages | `journalctl` |
| **Text files** in `/var/log` | Written by `rsyslog` (a copy of journal messages) and by applications such as nginx | `less`, `tail`, `grep` |

On Ubuntu, `rsyslog` copies journal messages into `/var/log/syslog` and `/var/log/auth.log`. On RHEL 9 and Rocky 9 it writes `/var/log/messages` and `/var/log/secure`. Amazon Linux 2023 does **not** install `rsyslog` by default, so the journal is the only system log there.

## Important log files

| What happened | Ubuntu / Debian | RHEL / Rocky |
|---|---|---|
| General system messages | `/var/log/syslog` | `/var/log/messages` |
| Logins, sudo, SSH | `/var/log/auth.log` | `/var/log/secure` |
| Kernel | `/var/log/kern.log`, `dmesg` | `dmesg`, `journalctl -k` |
| Package installs | `/var/log/apt/history.log`, `/var/log/dpkg.log` | `/var/log/dnf.log`, `dnf history` |
| Boot | `journalctl -b` | `journalctl -b`, `/var/log/boot.log` |
| cloud-init (first boot) | `/var/log/cloud-init.log`, `/var/log/cloud-init-output.log` | same |
| Azure agent | `/var/log/waagent.log` | same |
| nginx | `/var/log/nginx/access.log`, `error.log` | same |
| Apache | `/var/log/apache2/` | `/var/log/httpd/` |

## journalctl

| Goal | Command |
|---|---|
| Everything, newest at the end | `journalctl` |
| Follow live | `journalctl -f` |
| One service | `journalctl -u nginx` |
| One service, live | `journalctl -u nginx -f` |
| Last 50 lines | `journalctl -u nginx -n 50` |
| Since a time | `journalctl --since "2026-09-23 09:00" --until "2026-09-23 10:00"` |
| Relative time | `journalctl --since "30 min ago"` |
| Current boot only | `journalctl -b` |
| Previous boot | `journalctl -b -1` |
| List boots | `journalctl --list-boots` |
| Errors and worse | `journalctl -p err -b` |
| Kernel messages | `journalctl -k` |
| One process ID | `journalctl _PID=1449` |
| No pager, for scripts | `journalctl -u nginx --no-pager` |
| Explain known errors | `journalctl -xe` |

Priorities from most to least severe: `emerg`, `alert`, `crit`, `err`, `warning`, `notice`, `info`, `debug`. `-p err` shows `err` and everything more severe.

**Example: why did the server reboot?**

```bash
journalctl --list-boots | tail -3
journalctl -b -1 -n 30 --no-pager
```

Output of `--list-boots` (example):

```text
 -2 5b1c... Sun 2026-09-21 02:00:04 UTC Mon 2026-09-22 02:00:09 UTC
 -1 9a7e... Mon 2026-09-22 02:00:31 UTC Tue 2026-09-23 03:14:55 UTC
  0 c3d2... Tue 2026-09-23 03:15:22 UTC Tue 2026-09-23 11:10:02 UTC
```

The last lines of boot `-1` show what happened just before the reboot: a clean shutdown by a user or updates, an out-of-memory kill, or nothing at all (which points to a crash or a host-level event, so check the cloud provider's activity log).

**Example: all errors from the last hour, all services:**

```bash
journalctl -p err --since "1 hour ago" --no-pager
```

### Make the journal persistent

If `/var/log/journal` does not exist, the journal may be stored only in memory (`/run/log/journal`) and is lost at reboot. Ubuntu and RHEL cloud images normally keep it on disk. Check and enable:

```bash
ls -d /var/log/journal || { sudo mkdir -p /var/log/journal && sudo systemctl restart systemd-journald; }
journalctl --disk-usage
```

### Limit journal size

```bash
sudo journalctl --vacuum-size=500M     # shrink now to 500 MB
sudo journalctl --vacuum-time=14d      # delete entries older than 14 days
```

Set a permanent limit in `/etc/systemd/journald.conf.d/size.conf`:

```ini
[Journal]
SystemMaxUse=500M
```

```bash
sudo mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=500M\n' | sudo tee /etc/systemd/journald.conf.d/size.conf
sudo systemctl restart systemd-journald
```

## Kernel messages: dmesg

`dmesg` shows messages from the kernel: disk errors, network card events, out-of-memory kills, and hardware changes such as a newly attached data disk.

```bash
sudo dmesg -T | tail -20
sudo dmesg -T --level=err,warn
```

Output (example, a new data disk attached):

```text
[Tue Sep 23 11:20:14 2026] sd 1:0:0:0: [sdc] 67108864 512-byte logical blocks: (34.4 GB/32.0 GiB)
[Tue Sep 23 11:20:14 2026] sd 1:0:0:0: [sdc] Attached SCSI disk
```

## Application logs

Web servers and most applications write their own files. Two lines worth memorising:

```bash
sudo tail -f /var/log/nginx/error.log
sudo awk '{print $9}' /var/log/nginx/access.log | sort | uniq -c | sort -rn
```

The second command counts HTTP status codes. A jump in `500` or `502` means the application behind nginx is failing.

## logrotate

Text logs grow forever unless something rotates them. `logrotate` runs daily (from a systemd timer or cron), renames the current log, compresses old ones, and deletes the oldest.

```bash
cat /etc/logrotate.d/nginx
```

Output (example):

```text
/var/log/nginx/*.log {
	daily
	missingok
	rotate 14
	compress
	delaycompress
	notifempty
	create 0640 www-data adm
	sharedscripts
	postrotate
		invoke-rc.d nginx rotate >/dev/null 2>&1
	endscript
}
```

| Directive | Meaning |
|---|---|
| `daily` / `weekly` | How often to rotate |
| `rotate 14` | Keep 14 old files |
| `compress` / `delaycompress` | gzip old files, but leave the newest old file uncompressed |
| `missingok` / `notifempty` | Do not complain if missing, skip if empty |
| `create 0640 user group` | Permissions of the new log file |
| `postrotate` | Command to run afterwards, usually to make the app reopen its log |
| `copytruncate` | Copy then empty the file, for apps that cannot reopen logs |

Add rotation for your own application in `/etc/logrotate.d/myapp`:

```text
/var/log/myapp/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
```

Test without changing anything:

```bash
sudo logrotate -d /etc/logrotate.d/myapp        # dry run, shows what would happen
sudo logrotate -f /etc/logrotate.d/myapp        # force a rotation now
```

## Sending logs off the server

Logs on the server disappear when the server is deleted, and an attacker with root can edit them. In production, forward logs to a central service:

| Cloud | Agent | Destination |
|---|---|---|
| Azure | Azure Monitor Agent with a Data Collection Rule | Log Analytics workspace |
| AWS | CloudWatch agent | CloudWatch Logs |
| Google Cloud | Ops Agent | Cloud Logging |

The cloud chapters (19, 20, 21) show where to find these.

## Lab: Trace a failed login and a failed service

1. From another machine, try to SSH with a user that does not exist: `ssh nosuchuser@<server-ip>`.
2. On the server, find the attempt:

```bash
sudo journalctl -u ssh --since "10 min ago" --no-pager | grep -i "invalid user"   # Ubuntu
sudo journalctl -u sshd --since "10 min ago" --no-pager | grep -i "invalid user"  # Red Hat family
```

Output (example):

```text
Sep 23 11:31:02 web01 sshd[5120]: Invalid user nosuchuser from 203.0.113.50 port 51234
```

3. Break the `myapp` service from Chapter 09 and find the reason using only `journalctl -u myapp -p err -b`.
4. Check how much space logs use: `sudo du -sh /var/log/* | sort -h | tail` and `journalctl --disk-usage`.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `/var/log/syslog` does not exist | Red Hat family or Amazon Linux. | Use `/var/log/messages` or `journalctl`. |
| `journalctl` shows nothing from before the reboot | Journal is not persistent. | Create `/var/log/journal` and restart `systemd-journald`. |
| Disk full because of logs | No rotation, or an app logging too much. | `du -sh /var/log/*`, `journalctl --vacuum-size`, add a logrotate rule. |
| Deleted a large log but space not freed | A process still has the file open. | `sudo lsof +L1`, then restart that service. Next time truncate: `sudo truncate -s 0 file`. |
| `No journal files were found` for a user | You are not in the `adm` or `systemd-journal` group. | Use `sudo journalctl`. |

## Next

[12. Storage and Filesystems](../12-storage-and-filesystems/README.md)
