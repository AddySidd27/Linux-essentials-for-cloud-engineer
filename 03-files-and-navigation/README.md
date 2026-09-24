# 03. Files and Navigation

Everything on a Linux server is organised as one tree of directories that starts at `/`. Configuration, logs, programs, and disks all appear somewhere in that tree. Knowing where things live is what lets you fix a server quickly.

## What you will learn

- The standard directory layout and what each directory is for
- Moving around with absolute and relative paths
- Creating, copying, moving, and deleting files safely
- Wildcards, redirection, pipes, and environment variables

## The directory tree

```text
/
├── bin, sbin, usr/   Programs (on modern systems bin and sbin point into /usr)
├── boot/             Kernel and bootloader files
├── dev/              Devices: disks (/dev/sda, /dev/nvme0n1), terminals
├── etc/              System configuration (text files)
├── home/             Home directories of normal users (/home/azureuser)
├── mnt/, media/      Temporary mount points (Azure uses /mnt for the temp disk)
├── opt/              Optional third-party software
├── proc/, sys/       Live kernel information (not real files on disk)
├── root/             Home directory of the root user
├── run/              Runtime data, cleared at boot (PID files, sockets)
├── srv/              Data served by this system (web or FTP content)
├── tmp/              Temporary files, may be cleared at boot
└── var/              Variable data: logs (/var/log), caches, databases, web root
```

Directories you will visit every day on a server:

| Path | What you find there |
|---|---|
| `/etc` | Configuration: `/etc/ssh/sshd_config`, `/etc/fstab`, `/etc/hosts` |
| `/var/log` | Log files |
| `/etc/systemd/system` | Your custom service definitions |
| `/home/<user>` | User files and `~/.ssh/authorized_keys` |
| `/var/www` | Default web content for nginx and Apache on Ubuntu |
| `/tmp` | Scratch space |

## Paths

- **Absolute path** starts with `/`: `/etc/ssh/sshd_config`. It works from anywhere.
- **Relative path** starts from where you are: `ssh/sshd_config` works only if you are in `/etc`.

| Symbol | Meaning |
|---|---|
| `~` | Your home directory |
| `.` | Current directory |
| `..` | Parent directory |
| `-` | Previous directory (with `cd`) |

## Moving around

```bash
pwd                 # print working directory
cd /var/log         # go to an absolute path
cd ..               # up one level, now in /var
cd -                # back to /var/log
cd                  # home directory
```

Output of `pwd` after `cd /var/log`:

```text
/var/log
```

## Listing files

```bash
ls -lah /etc/ssh
```

Output (example):

```text
total 604K
drwxr-xr-x   4 root root 4.0K Sep 10 09:12 .
drwxr-xr-x 104 root root 4.0K Sep 22 06:40 ..
-rw-r--r--   1 root root 573K Apr  5 12:00 moduli
-rw-r--r--   1 root root 1.6K Apr  5 12:00 ssh_config
-rw-r--r--   1 root root 3.3K Sep 10 09:12 sshd_config
-rw-------   1 root root  505 Sep 10 09:12 ssh_host_ecdsa_key
-rw-r--r--   1 root root  173 Sep 10 09:12 ssh_host_ecdsa_key.pub
```

Read each line like this:

```text
-rw-r--r--   1  root  root  3.3K  Sep 10 09:12  sshd_config
|            |  |     |     |     |             |
type+perms   |  owner group size  last modified name
             link count
```

- First character: `-` file, `d` directory, `l` symbolic link.
- `-a` shows hidden files (names starting with `.`). `-h` shows human-readable sizes. `-t` sorts by time, newest first.

Useful variations:

```bash
ls -lt /var/log | head          # most recently changed logs
ls -ld /var/www                 # details of the directory itself, not its contents
tree -L 2 /etc/nginx            # tree view (install with: sudo apt install tree)
```

## Creating files and directories

```bash
mkdir -p ~/projects/app/logs    # -p creates parent directories as needed
touch ~/projects/app/app.conf   # empty file, or update the timestamp of an existing one
echo "port=8080" > ~/projects/app/app.conf
```

## Copying, moving, renaming

```bash
cp app.conf app.conf.bak                  # copy a file
cp -r ~/projects/app /tmp/app-copy        # copy a directory (-r = recursive)
cp -a /var/www/html /backup/html          # archive mode: keeps permissions, owners, times
mv app.conf.bak /tmp/                     # move
mv old-name.txt new-name.txt              # rename (same command)
```

> **Always back up a config file before you edit it:**
> `sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.$(date +%F)`
> This creates `sshd_config.2026-09-23`, so you can restore it if the edit goes wrong.

## Deleting

```bash
rm file.txt              # delete a file
rm -i *.log              # ask before each delete
rmdir emptydir           # delete an empty directory
rm -r olddir             # delete a directory and everything in it
```

There is no undo. Two habits prevent most accidents:

1. Run `ls` with the same pattern first: `ls /tmp/app-*`, then `rm -r /tmp/app-*`.
2. Never run `rm -rf` with a variable you have not checked. `rm -rf "$DIR/"` with an empty `$DIR` becomes `rm -rf /`.

## Links

```bash
ln -s /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app
ls -l /etc/nginx/sites-enabled/
```

Output (example):

```text
lrwxrwxrwx 1 root root 34 Sep 23 10:00 app -> /etc/nginx/sites-available/app
```

A **symbolic link** is a shortcut that points to another path. nginx on Ubuntu enables sites this way. If the target is deleted, the link breaks.

## Wildcards (globbing)

| Pattern | Matches |
|---|---|
| `*` | Any number of characters: `*.log` |
| `?` | Exactly one character: `file?.txt` matches `file1.txt` |
| `[0-9]` | One character from a range: `app[0-9].log` |
| `{a,b}` | Each listed word: `cp app.conf{,.bak}` expands to `cp app.conf app.conf.bak` |

## Redirection and pipes

Every command has three streams: standard input (0), standard output (1), and standard error (2).

```bash
ls /etc > files.txt          # write output to a file (overwrite)
ls /var >> files.txt         # append
ls /nope 2> errors.txt       # write only errors to a file
ls /etc /nope &> all.txt     # write output and errors
command > /dev/null 2>&1     # discard everything (common in scripts and cron)
```

A **pipe** (`|`) sends the output of one command into the next:

```bash
ls /etc | wc -l                     # how many entries in /etc
ps aux | grep nginx                 # find nginx processes
```

Writing to a root-owned file with sudo needs `tee`, because the redirection runs as your normal user:

```bash
echo "10.0.1.20 db01" | sudo tee -a /etc/hosts
```

`sudo echo "..." >> /etc/hosts` fails with `Permission denied`.

## Environment variables

```bash
echo "$HOME"          # your home directory
echo "$PATH"          # directories searched for commands
env | sort | less     # all variables
export APP_ENV=prod   # set for this shell and programs it starts
```

Make a variable permanent for your user by adding the `export` line to `~/.bashrc`, then run `source ~/.bashrc`.

## Command history and shortcuts

| Keys or command | Action |
|---|---|
| `Up` / `Down` | Previous / next command |
| `Ctrl+R` | Search history, type part of an old command |
| `Tab` | Complete file names and commands |
| `Ctrl+C` | Stop the running command |
| `Ctrl+L` or `clear` | Clear the screen |
| `history \| tail -20` | Last 20 commands |
| `!!` | Repeat the last command (`sudo !!` reruns it with sudo) |

## Lab: Organise an application directory

```bash
mkdir -p ~/lab03/app/{config,logs,data}
cd ~/lab03/app
echo "port=8080" > config/app.conf
for i in 1 2 3; do echo "entry $i" > "logs/app-$i.log"; done
ls -R
cp config/app.conf{,.bak}
ls config
mv logs/app-1.log logs/app-1.log.old
ls logs/*.log
tar -czf ~/lab03-backup.tar.gz -C ~/lab03 app
ls -lh ~/lab03-backup.tar.gz
```

Output (last three commands, example):

```text
logs/app-2.log  logs/app-3.log
-rw-r--r-- 1 azureuser azureuser 412 Sep 23 10:20 /home/azureuser/lab03-backup.tar.gz
```

**Check yourself:** Why did `ls logs/*.log` not show `app-1.log.old`? (The pattern requires the name to end in `.log`.)

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `No such file or directory` | Wrong path, or a relative path used from the wrong place. | Run `pwd`. Use the absolute path. Use `Tab` to complete. |
| `Is a directory` when using `cp` | Copying a directory without `-r`. | `cp -r` or `cp -a`. |
| `Permission denied` when writing to `/etc` | Normal users cannot write there. | `sudo`, or `sudo tee` for redirection. |
| File name with spaces breaks a command | The shell splits on spaces. | Quote it: `"my file.txt"`. |

## Next

[04. Reading and Searching Text](../04-reading-and-searching-text/README.md)
