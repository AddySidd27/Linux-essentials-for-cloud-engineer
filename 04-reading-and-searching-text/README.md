# 04. Reading and Searching Text

Linux stores configuration and logs as plain text. When something breaks, most of your time goes into reading files, finding the right lines, and counting how often something happened. These are the tools for that.

## What you will learn

- Reading files of any size: `cat`, `less`, `head`, `tail`
- Searching inside files with `grep`
- Finding files with `find`
- Slicing and summarising text with `cut`, `sort`, `uniq`, `wc`, `awk`, and `sed`
- Compressing and archiving with `tar` and `gzip`

## Practice file

Create a small access log to use in the examples:

```bash
cat > ~/access.log <<'EOF'
10.0.0.5 - - [23/Sep/2026:10:01:02] "GET /index.html" 200 512
10.0.0.8 - - [23/Sep/2026:10:01:05] "GET /login" 200 1024
10.0.0.5 - - [23/Sep/2026:10:02:11] "POST /login" 401 128
10.0.0.9 - - [23/Sep/2026:10:02:40] "GET /admin" 403 64
10.0.0.5 - - [23/Sep/2026:10:03:00] "POST /login" 401 128
10.0.0.8 - - [23/Sep/2026:10:04:15] "GET /api/health" 500 32
10.0.0.5 - - [23/Sep/2026:10:05:30] "POST /login" 200 256
EOF
```

`<<'EOF' ... EOF` is a **here-document**. It writes everything between the markers into the file.

## Reading files

| Command | Use it when |
|---|---|
| `cat file` | The file is short |
| `less file` | The file is long. Scroll with arrows, `/text` to search, `n` for next match, `G` for end, `q` to quit |
| `head -n 20 file` | You want the first 20 lines |
| `tail -n 20 file` | You want the last 20 lines |
| `tail -f file` | You want to watch new lines as they are written. `Ctrl+C` to stop |

```bash
tail -n 2 ~/access.log
```

Output:

```text
10.0.0.8 - - [23/Sep/2026:10:04:15] "GET /api/health" 500 32
10.0.0.5 - - [23/Sep/2026:10:05:30] "POST /login" 200 256
```

Watching a log while you reproduce a problem is one of the most useful habits you can build:

```bash
sudo tail -f /var/log/nginx/error.log
```

## grep: find lines that match

```bash
grep "POST" ~/access.log
```

Output:

```text
10.0.0.5 - - [23/Sep/2026:10:02:11] "POST /login" 401 128
10.0.0.5 - - [23/Sep/2026:10:03:00] "POST /login" 401 128
10.0.0.5 - - [23/Sep/2026:10:05:30] "POST /login" 200 256
```

Options you will use constantly:

| Option | Meaning | Example |
|---|---|---|
| `-i` | Ignore case | `grep -i error app.log` |
| `-v` | Show lines that do **not** match | `grep -v '^#' sshd_config` |
| `-c` | Count matching lines | `grep -c 401 access.log` |
| `-n` | Show line numbers | `grep -n Port /etc/ssh/sshd_config` |
| `-r` | Search a directory recursively | `grep -r "listen" /etc/nginx/` |
| `-l` | Show only file names | `grep -rl "10.0.1.20" /etc` |
| `-E` | Extended regular expressions | `grep -E " (401\|403) " access.log` |
| `-A 3` / `-B 3` | Show 3 lines after / before each match | `grep -A 3 "Traceback" app.log` |

Show a config file without comments and blank lines:

```bash
grep -Ev '^\s*(#|$)' /etc/ssh/sshd_config
```

Output (example):

```text
Include /etc/ssh/sshd_config.d/*.conf
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem	sftp	/usr/lib/openssh/sftp-server
```

## Regular expression basics

| Pattern | Matches |
|---|---|
| `^text` | `text` at the start of a line |
| `text$` | `text` at the end of a line |
| `.` | Any single character |
| `.*` | Any characters, any length |
| `[0-9]+` | One or more digits (with `-E`) |
| `\s` | Whitespace |

## find: locate files

```bash
find /etc -name "*.conf"                    # by name
find /var/log -name "*.gz" -mtime +7        # compressed logs older than 7 days
find / -xdev -type f -size +500M 2>/dev/null   # files over 500 MB on the root filesystem
find /home -user azureuser -type f          # files owned by a user
find /tmp -type f -mmin -30                 # changed in the last 30 minutes
```

`-xdev` keeps `find` on one filesystem, so it does not scan mounted data disks or `/proc`.

Act on what you find:

```bash
find /var/log/myapp -name "*.log" -mtime +30 -print            # always preview first
find /var/log/myapp -name "*.log" -mtime +30 -delete           # then delete
```

## Counting and summarising

**How many requests failed with 401?**

```bash
grep -c '" 401 ' ~/access.log
```

Output:

```text
2
```

**Which IP addresses made the most requests?**

```bash
awk '{print $1}' ~/access.log | sort | uniq -c | sort -rn
```

Output:

```text
      4 10.0.0.5
      2 10.0.0.8
      1 10.0.0.9
```

How it works: `awk` prints the first field, `sort` groups identical lines, `uniq -c` counts them, and `sort -rn` sorts by number, highest first. This pattern (`sort | uniq -c | sort -rn`) answers most "top N" questions.

**Count requests per status code:**

```bash
awk '{print $(NF-1)}' ~/access.log | sort | uniq -c
```

Output:

```text
      3 200
      2 401
      1 403
      1 500
```

`NF` is the number of fields on the line, so `$(NF-1)` is the second-to-last field.

## cut, wc, sort

```bash
cut -d: -f1 /etc/passwd | head -3        # first field, colon-separated
wc -l ~/access.log                       # number of lines
sort -k2 -t: /etc/group | head -3        # sort by second field
```

Output of `cut` (example):

```text
root
daemon
bin
```

## awk: pick columns and filter

```bash
awk '$NF > 200 {print $1, $NF}' ~/access.log       # lines where last field > 200
df -h | awk 'NR>1 && $5+0 > 80 {print $6, $5}'      # filesystems over 80% full
```

`NR` is the line number. `NR>1` skips the header line. `$5+0` turns `85%` into the number `85`.

## sed: edit text in a stream

```bash
sed 's/GET/READ/' ~/access.log | head -2          # replace first match on each line (output only)
sed -n '3,5p' ~/access.log                        # print lines 3 to 5
```

Edit a file in place, keeping a backup:

```bash
sudo sed -i.bak 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
```

`-i.bak` edits the file and saves the original as `sshd_config.bak`. Always check the result with `grep` before restarting a service.

## Compare files

```bash
diff /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
```

Output (example):

```text
57c57
< #PasswordAuthentication yes
---
> PasswordAuthentication no
```

## Archives and compression

```bash
tar -czf backup.tar.gz /etc/nginx        # create a gzip-compressed archive
tar -tzf backup.tar.gz | head            # list contents without extracting
tar -xzf backup.tar.gz -C /tmp/restore   # extract into a directory (it must exist)
gzip big.log                             # compress, creates big.log.gz
zcat big.log.gz | grep ERROR             # search a compressed file without extracting
```

| Letter | Meaning |
|---|---|
| `c` | create |
| `x` | extract |
| `t` | list |
| `z` | gzip compression |
| `f` | file name follows |
| `v` | verbose |

## Lab: Investigate a login attack

Using `~/access.log`:

1. Find every failed login (status 401).
2. Find which IP produced them.
3. Check whether that IP eventually logged in successfully.

```bash
grep 'POST /login" 401' ~/access.log
grep 'POST /login" 401' ~/access.log | awk '{print $1}' | sort | uniq -c
grep '10.0.0.5' ~/access.log | grep 'POST /login" 200'
```

Output of the last command:

```text
10.0.0.5 - - [23/Sep/2026:10:05:30] "POST /login" 200 256
```

The same IP failed twice and then succeeded. In a real incident you would check whether that was the real user or a guessed password.

Try the same on a real server:

```bash
sudo grep "Failed password" /var/log/auth.log | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head
```

On Red Hat family systems the file is `/var/log/secure`, or use `journalctl -u sshd` (Chapter 11).

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `grep` finds nothing, but you can see the text | Case mismatch, or special characters in the pattern. | Use `-i`. Put the pattern in single quotes. Use `-F` for a fixed string. |
| `find` prints many `Permission denied` lines | Normal user cannot read some directories. | Use `sudo`, or add `2>/dev/null`. |
| `sed -i` broke a config file | The pattern matched more than expected. | Restore the `.bak` copy. Test without `-i` first. |

## Next

[05. Editing Files](../05-editing-files/README.md)
