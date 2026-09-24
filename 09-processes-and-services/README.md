# 09. Processes and Services

A **process** is a running program. A **service** is a process that the system starts and keeps running in the background, such as a web server or the SSH server. On every modern distribution, services are managed by **systemd**. Starting, stopping, and troubleshooting services is daily work.

## What you will learn

- Viewing and controlling processes: `ps`, `top`, `kill`, signals
- Managing services with `systemctl`
- Reading a unit file and writing your own service
- Changing a service safely with overrides
- Background jobs and keeping commands running after you log out

## Processes

```bash
ps aux | head -5
```

Output (example):

```text
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.1  22412 13200 ?        Ss   Sep11   0:12 /sbin/init
root         612  0.0  0.1  12000  7000 ?        Ss   Sep11   0:00 sshd: /usr/sbin/sshd -D
www-data    1450  0.0  0.1  55800  5600 ?        S    09:55   0:00 nginx: worker process
```

| Column | Meaning |
|---|---|
| PID | Process ID |
| %CPU / %MEM | Resource use |
| RSS | Real memory in use (KB) |
| STAT | `R` running, `S` sleeping, `D` waiting on disk (cannot be interrupted), `Z` zombie |
| COMMAND | What is running |

Useful forms:

```bash
ps -ef --forest                          # parent/child tree
ps aux --sort=-%mem | head -6            # top memory users
ps aux --sort=-%cpu | head -6            # top CPU users
pgrep -a nginx                           # PIDs and command lines matching a name
pstree -p                                # tree with PIDs
```

### top

```bash
top
```

Inside `top`: `P` sort by CPU, `M` sort by memory, `1` show each CPU, `k` kill a PID, `q` quit. `htop` (`sudo apt install htop`) is easier to read. Chapter 17 explains what the numbers mean.

### Signals

`kill` sends a signal to a process. It does not always "kill".

| Signal | Number | Effect |
|---|---|---|
| `SIGTERM` | 15 | Ask the process to stop cleanly. Default for `kill`. |
| `SIGKILL` | 9 | Force stop immediately. No cleanup. Last resort. |
| `SIGHUP` | 1 | Many daemons reload their config on this. |
| `SIGINT` | 2 | Same as `Ctrl+C`. |

```bash
kill 1450              # polite stop
kill -9 1450           # forced stop
pkill -f "python3 app.py"   # by command line
```

Always try `SIGTERM` first. A service managed by systemd should be stopped with `systemctl stop`, otherwise systemd may simply restart it.

## Services with systemctl

| Task | Command |
|---|---|
| Status, recent log lines | `systemctl status nginx` |
| Start / stop / restart | `sudo systemctl start\|stop\|restart nginx` |
| Reload config without dropping connections | `sudo systemctl reload nginx` |
| Start at boot | `sudo systemctl enable nginx` |
| Enable and start now | `sudo systemctl enable --now nginx` |
| Do not start at boot | `sudo systemctl disable nginx` |
| Is it running? Enabled? | `systemctl is-active nginx`, `systemctl is-enabled nginx` |
| All failed units | `systemctl --failed` |
| All running services | `systemctl list-units --type=service --state=running` |
| Prevent any start | `sudo systemctl mask nginx` (undo with `unmask`) |

```bash
systemctl status nginx
```

Output (example):

```text
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled; preset: enabled)
     Active: active (running) since Tue 2026-09-23 09:55:12 UTC; 2h ago
       Docs: man:nginx(8)
   Main PID: 1449 (nginx)
      Tasks: 3 (limit: 9387)
     Memory: 4.2M (peak: 4.6M)
        CPU: 52ms
     CGroup: /system.slice/nginx.service
             ├─1449 "nginx: master process /usr/sbin/nginx -g daemon on; master_process on;"
             └─1450 "nginx: worker process"

Sep 23 09:55:12 web01 systemd[1]: Started nginx.service - A high performance web server...
```

Read it top to bottom:

- **Loaded**: where the unit file is, and `enabled` means it starts at boot.
- **Active**: current state and since when. `failed` or `activating (auto-restart)` means trouble.
- The last lines are the most recent log messages. For more: `journalctl -u nginx -n 50`.

> Service names differ by distribution. The SSH server is `ssh` on Ubuntu and `sshd` on Red Hat family. The Apache web server is `apache2` on Ubuntu and `httpd` on Red Hat family.
>
> On Ubuntu 24.04, SSH is **socket-activated**: `ssh.socket` listens on port 22 and starts `ssh.service` on the first connection. Right after boot, `systemctl is-active ssh` can say `inactive` while SSH works fine. Check `systemctl status ssh.socket` instead.

## Unit files

A unit file tells systemd how to run a service.

| Location | Who writes it |
|---|---|
| `/usr/lib/systemd/system/` (or `/lib/systemd/system/`) | Packages. Do not edit, updates overwrite it. |
| `/etc/systemd/system/` | You. Files here take priority. |
| `/etc/systemd/system/<name>.service.d/*.conf` | Overrides (drop-ins) that change part of a unit. |

```bash
systemctl cat nginx
```

Shows the unit file plus any overrides, so you see exactly what systemd is using.

## Write your own service

This example runs a small Python web app as the `myapp` service account (created in [Chapter 06](../06-users-groups-and-sudo/README.md#service-accounts)).

**1. The application**

```bash
sudo mkdir -p /opt/myapp
sudo tee /opt/myapp/app.py > /dev/null <<'EOF'
import http.server, os, socketserver
PORT = int(os.environ.get("PORT", "8080"))
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"myapp is running\n")
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"listening on {PORT}", flush=True)
    httpd.serve_forever()
EOF
sudo useradd --system --no-create-home --shell /usr/sbin/nologin myapp 2>/dev/null || true
```

The `allow_reuse_address` line lets the app bind to port 8080 again straight after a crash. Without it, a restart within about a minute fails with `Address already in use`, because the old connections are still closing.

**2. The unit file**

```bash
sudo tee /etc/systemd/system/myapp.service > /dev/null <<'EOF'
[Unit]
Description=My sample web app
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=myapp
Group=myapp
Environment=PORT=8080
ExecStart=/usr/bin/python3 /opt/myapp/app.py
Restart=on-failure
RestartSec=5

# Basic hardening
NoNewPrivileges=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
```

| Setting | Meaning |
|---|---|
| `After=` / `Wants=` | Start after the network is up. |
| `User=` / `Group=` | Run as a non-root account. |
| `ExecStart=` | The command. Must be a full path. |
| `Restart=on-failure` | Restart if it crashes, but not if you stop it. |
| `WantedBy=multi-user.target` | Start at normal boot when enabled. |

**3. Load and start**

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now myapp
systemctl status myapp --no-pager
curl -s localhost:8080
```

Output of `curl`:

```text
myapp is running
```

`daemon-reload` is required every time you create or change a unit file.

**4. Test automatic restart**

Simulate a crash by killing the process with `SIGKILL`:

```bash
sudo pkill -9 -f /opt/myapp/app.py
sleep 6
systemctl is-active myapp
journalctl -u myapp -n 4 --no-pager
```

Output (example):

```text
active
Sep 23 12:20:30 web01 systemd[1]: myapp.service: Failed with result 'signal'.
Sep 23 12:20:35 web01 systemd[1]: myapp.service: Scheduled restart job, restart counter is at 1.
Sep 23 12:20:35 web01 systemd[1]: Started myapp.service - My sample web app.
Sep 23 12:20:35 web01 python3[2636]: listening on 8080
```

Now try `sudo pkill -f /opt/myapp/app.py` without `-9`. That sends `SIGTERM`, which systemd treats as a clean stop, so `Restart=on-failure` does **not** start it again and `systemctl is-active myapp` shows `inactive`. Start it with `sudo systemctl start myapp`. Use `Restart=always` if a service must come back even after a clean exit.

## Change a service without editing the original

```bash
sudo systemctl edit myapp
```

An editor opens. Add only what you want to change:

```ini
[Service]
Environment=PORT=9090
```

Save, then:

```bash
sudo systemctl restart myapp
systemctl cat myapp        # shows the original and your override
curl -s localhost:9090
```

The override is stored in `/etc/systemd/system/myapp.service.d/override.conf`. Package updates will not remove it. Remove it with `sudo systemctl revert myapp`.

## Background jobs and long commands

| Need | Use |
|---|---|
| Run in background in this shell | `command &`, list with `jobs`, bring back with `fg` |
| Keep running after logout (quick) | `nohup long-task.sh > task.log 2>&1 &` |
| Reattach later from another SSH session | `tmux` (`tmux new -s work`, detach `Ctrl+B` then `D`, reattach `tmux attach -t work`) |
| Run permanently | A systemd service (above) |

`tmux` is strongly recommended for long maintenance tasks over SSH. If your connection drops during an upgrade, the upgrade keeps running and you can reattach.

## Boot targets

```bash
systemctl get-default            # graphical.target or multi-user.target
systemctl list-dependencies multi-user.target | head
systemd-analyze blame | head     # what slowed the boot
```

Ubuntu cloud images report `graphical.target` even though no desktop is installed. It includes everything in `multi-user.target`, so both mean "normal server boot".

## Lab: Break the service and fix it

1. Change `ExecStart` in `/etc/systemd/system/myapp.service` to `/usr/bin/python3 /opt/myapp/missing.py`.
2. Run `sudo systemctl daemon-reload && sudo systemctl restart myapp`.
3. Diagnose:

```bash
systemctl status myapp --no-pager
journalctl -u myapp -n 20 --no-pager
```

Output (example):

```text
     Active: activating (auto-restart) (Result: exit-code) since ...
myapp[2231]: /usr/bin/python3: can't open file '/opt/myapp/missing.py': [Errno 2] No such file or directory
systemd[1]: myapp.service: Main process exited, code=exited, status=2/INVALIDARGUMENT
```

4. Fix the path, `daemon-reload`, restart, and confirm with `curl`.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `Unit myapp.service not found` | File not in `/etc/systemd/system` or no `daemon-reload`. | Check the path, run `sudo systemctl daemon-reload`. |
| `status=203/EXEC` | `ExecStart` path wrong or not executable. | Use a full path. `ls -l` the file. |
| `status=217/USER` | `User=` account does not exist. | Create it with `useradd --system`. |
| `Address already in use` | Another process owns the port. | `sudo ss -ltnp 'sport = :8080'`. |
| Service keeps restarting | App crashes on start. | `journalctl -u <name> -b` shows why. |
| Changes to unit file ignored | Missing `daemon-reload`. | Run it, then restart. |

## Next

[10. Scheduling Jobs](../10-scheduling-jobs/README.md)
