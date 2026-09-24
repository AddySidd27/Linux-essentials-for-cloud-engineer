# 16. Bash Scripting

When you do the same steps on ten servers, or every morning, write a script. Scripts make work repeatable, reviewable, and fast. This chapter teaches the parts of Bash you need for operations work and shows how to write scripts that fail safely.

## What you will learn

- Script structure and running a script
- Variables, quoting, arguments, and user input
- Conditions, loops, and functions
- Exit codes and error handling with `set -euo pipefail`
- Logging, locking, and testing scripts
- Three complete scripts in [`examples/`](examples/)

## Your first script

```bash
cat > hello.sh <<'EOF'
#!/usr/bin/env bash
echo "Hello from $(hostname) at $(date +%H:%M)"
EOF
chmod +x hello.sh
./hello.sh
```

Output (example):

```text
Hello from web01 at 12:10
```

- The first line (**shebang**) says which interpreter runs the file.
- `chmod +x` makes it executable. Without it, run it as `bash hello.sh`.
- `./` is needed because the current directory is not in `PATH`.

## Variables and quoting

```bash
name="web01"
count=3
echo "Server: $name, checks: $count"
echo "Home is ${HOME}"
today=$(date +%F)          # command substitution
echo 'Single quotes print $name literally'
```

Output:

```text
Server: web01, checks: 3
Home is /home/azureuser
Single quotes print $name literally
```

Rules:

- No spaces around `=`: `name=web01`, not `name = web01`.
- **Always quote variables**: `"$file"`. Unquoted variables split on spaces and expand wildcards, which is the cause of many dangerous bugs.
- Use `${var}` when the name touches other text: `"${name}_backup"`.

Default values:

```bash
port="${PORT:-8080}"       # use $PORT if set, otherwise 8080
dir="${1:?Usage: $0 <directory>}"   # stop with a message if the first argument is missing
```

## Arguments

| Variable | Meaning |
|---|---|
| `$0` | Script name |
| `$1`, `$2` ... | Arguments |
| `$#` | Number of arguments |
| `"$@"` | All arguments, each kept separate |
| `$?` | Exit code of the last command |
| `$$` | PID of the script |

```bash
#!/usr/bin/env bash
echo "Script: $0, got $# arguments"
for arg in "$@"; do
  echo " - $arg"
done
```

## Exit codes

Every command returns a number: `0` means success, anything else means failure.

```bash
grep -q nginx /etc/passwd
echo $?
```

Output:

```text
1
```

`1` because the text was not found. Scripts use exit codes to decide what to do next, and cron, systemd, and CI tools use your script's exit code to decide if it worked. End your script with `exit 0` or `exit 1` deliberately.

## Conditions

```bash
if systemctl is-active --quiet nginx; then
  echo "nginx running"
else
  echo "nginx NOT running"
fi
```

Tests inside `[[ ]]`:

| Test | True when |
|---|---|
| `-f file` | File exists |
| `-d dir` | Directory exists |
| `-x file` | File is executable |
| `-z "$s"` / `-n "$s"` | String is empty / not empty |
| `"$a" == "$b"` | Strings are equal |
| `$a -gt $b` | Number greater than (`-lt`, `-ge`, `-le`, `-eq`, `-ne`) |

```bash
usage=$(df --output=pcent / | tail -1 | tr -dc '0-9')
if [[ $usage -ge 90 ]]; then
  echo "CRITICAL: root at ${usage}%"
elif [[ $usage -ge 80 ]]; then
  echo "WARNING: root at ${usage}%"
else
  echo "OK: root at ${usage}%"
fi
```

Short forms: `cmd1 && cmd2` runs `cmd2` only if `cmd1` succeeded. `cmd1 || cmd2` runs `cmd2` only if `cmd1` failed.

```bash
mkdir -p /backup && echo "ready"
systemctl is-active --quiet nginx || sudo systemctl start nginx
```

## case

```bash
case "$1" in
  start)   sudo systemctl start myapp ;;
  stop)    sudo systemctl stop myapp ;;
  status)  systemctl status myapp --no-pager ;;
  *)       echo "Usage: $0 {start|stop|status}"; exit 1 ;;
esac
```

## Loops

```bash
for svc in nginx ssh.socket cron; do
  printf '%-11s %s\n' "$svc" "$(systemctl is-active "$svc")"
done
```

Output (example):

```text
nginx       active
ssh.socket  active
cron        active
```

On Ubuntu 24.04, check `ssh.socket`, not `ssh`: the SSH service is started on demand and can be `inactive` while SSH works (Chapter 09). On the Red Hat family, use `sshd`.

Read a file line by line (the safe way):

```bash
while IFS= read -r host; do
  [[ -z "$host" || "$host" == \#* ]] && continue    # skip blank lines and comments
  echo "Checking $host"
done < servers.txt
```

Retry until something succeeds:

```bash
for attempt in {1..10}; do
  curl -fsS http://localhost:8080/ >/dev/null && { echo "up"; break; }
  echo "attempt $attempt failed, waiting"
  sleep 3
done
```

## Functions

```bash
log() {
  echo "$(date -Is) [$1] ${*:2}"
}

check_service() {
  local svc="$1"
  if systemctl is-active --quiet "$svc"; then
    log INFO "$svc is running"
  else
    log ERROR "$svc is not running"
    return 1
  fi
}

check_service nginx
```

Use `local` for variables inside functions so they do not overwrite variables elsewhere.

## Safe scripts: strict mode

Start operational scripts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

| Option | Effect |
|---|---|
| `-e` | Stop at the first command that fails |
| `-u` | Stop if you use a variable that was never set (catches typos) |
| `-o pipefail` | A pipeline fails if any command in it fails, not just the last |

Without these, a script continues after a failed `cd` and runs the next command in the wrong directory.

```bash
cd /var/app/releases        # if this fails without -e ...
rm -rf ./*                  # ... this runs in whatever directory you were in
```

Clean up on exit, even after an error:

```bash
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
```

Prevent two copies running at once (useful for cron jobs that can overlap):

```bash
exec 9>/var/lock/backup.lock
flock -n 9 || { echo "already running"; exit 1; }
```

## Logging from scripts

```bash
logger -t backup "backup finished, 42 files"
journalctl -t backup -n 5
```

`logger` writes to the system journal, so your script's messages appear alongside everything else and reach central logging.

## Check your scripts

```bash
bash -n script.sh          # syntax check only
bash -x script.sh          # run and print each command (debugging)
shellcheck script.sh       # finds common bugs (sudo apt install shellcheck)
```

`shellcheck` catches unquoted variables, useless `cat`, wrong tests, and much more. Run it on every script before you trust it.

## Example scripts

The [`examples/`](examples/) directory contains complete scripts that pass `shellcheck`:

| Script | What it does |
|---|---|
| [`health-check.sh`](examples/health-check.sh) | Checks CPU load, memory, disk, and a list of services. Exits non-zero if something is wrong, so it can drive alerts. |
| [`backup-dir.sh`](examples/backup-dir.sh) | Creates a dated, compressed backup of a directory, keeps the last N copies, and uses a lock. |
| [`disk-alert.sh`](examples/disk-alert.sh) | Reports every filesystem above a threshold. |

Try them:

```bash
chmod +x examples/*.sh
./examples/health-check.sh nginx ssh.socket
sudo ./examples/backup-dir.sh /etc /var/backups/etc 7
./examples/disk-alert.sh 80
```

Output of `health-check.sh` (example):

```text
2026-09-23T12:30:00+00:00 OK    load 0.08 (2 CPUs)
2026-09-23T12:30:00+00:00 OK    memory 18% used
2026-09-23T12:30:00+00:00 OK    / 11% used
2026-09-23T12:30:00+00:00 OK    service nginx active
2026-09-23T12:30:00+00:00 OK    service ssh.socket active
RESULT: healthy
```

## Lab: Automate a daily check

1. Copy `health-check.sh` to `/usr/local/bin/health-check`.
2. Create a systemd service and timer (Chapter 10) that run it every day at 07:00 with `nginx` and `ssh.socket` as arguments.
3. Stop nginx and run the service manually: `sudo systemctl start health-check.service`.
4. Confirm the failure appears in `journalctl -u health-check.service` and that `systemctl status` shows the unit as failed.
5. Start nginx again and confirm the next run is healthy.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `$'\r': command not found` | Windows line endings. | `sed -i 's/\r$//' script.sh`. Set your editor to LF. |
| `Permission denied` running `./script.sh` | Not executable, or on a `noexec` mount. | `chmod +x`, or `bash script.sh`. |
| `[: too many arguments` | Unquoted variable with spaces. | Quote it and use `[[ ]]`. |
| Script works in terminal, fails in cron | Different `PATH` and environment. | Full paths, set `PATH` at the top. |
| `unbound variable` after adding `set -u` | A variable that may be empty. | Use `"${var:-}"` or give a default. |

## Next

[17. Performance and Monitoring](../17-performance-and-monitoring/README.md)
