# 05. Editing Files

Servers do not have a graphical editor. You edit configuration files in the terminal, usually over SSH. Learn `nano` first because it is easy. Learn the basics of `vim` because it is installed almost everywhere, including rescue environments and minimal images where `nano` is missing.

## What you will learn

- Editing with `nano`
- The minimum `vim` you need to survive
- Editing system files safely with `sudo`, backups, and validation

## nano

```bash
nano ~/notes.txt
sudo nano /etc/hosts
```

The shortcuts are listed at the bottom of the screen. `^` means `Ctrl`.

| Keys | Action |
|---|---|
| `Ctrl+O`, then `Enter` | Save |
| `Ctrl+X` | Exit (asks to save if there are changes) |
| `Ctrl+W` | Search |
| `Ctrl+\` | Search and replace |
| `Ctrl+K` / `Ctrl+U` | Cut line / paste |
| `Ctrl+_` then a number | Go to line number |
| `Alt+U` | Undo |

Open a file directly at a line (useful when an error message says "line 42"):

```bash
nano +42 /etc/nginx/nginx.conf
```

## vim

`vim` has **modes**. This is what confuses beginners.

| Mode | How you get there | What keys do |
|---|---|---|
| Normal | `Esc` | Keys are commands (move, delete, save) |
| Insert | `i` | Keys type text |
| Command line | `:` from Normal mode | Run commands like save and quit |

The survival sequence:

1. `vim file.txt`
2. Press `i` and type your change.
3. Press `Esc`.
4. Type `:wq` and press `Enter` to save and quit.

To quit **without** saving: `Esc`, then `:q!`, then `Enter`.

Commands in Normal mode:

| Keys | Action |
|---|---|
| `gg` / `G` | Go to first / last line |
| `:42` | Go to line 42 |
| `/text`, then `n` | Search forward, next match |
| `dd` | Delete (cut) the current line |
| `yy` / `p` | Copy line / paste below |
| `u` / `Ctrl+R` | Undo / redo |
| `o` | New line below and enter Insert mode |
| `:%s/old/new/g` | Replace all `old` with `new` in the file |
| `:set number` | Show line numbers |

If your screen fills with odd characters or you are not sure which mode you are in, press `Esc` twice.

## Edit system files safely

Three rules protect you from turning a small change into an outage:

1. **Back up first.**
2. **Validate before you restart.** Most services can test their own configuration.
3. **Keep your current session open** when changing SSH or firewall settings, and test from a second session.

```bash
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.$(date +%F)
sudo nano /etc/nginx/nginx.conf
sudo nginx -t
```

Output of `nginx -t` when the file is valid:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Only then:

```bash
sudo systemctl reload nginx
```

Validation commands for common services:

| Service | Test command |
|---|---|
| nginx | `sudo nginx -t` |
| Apache | `sudo apachectl configtest` |
| SSH server | `sudo sshd -t` (no output means OK) |
| sudoers | `sudo visudo -c` |
| fstab | `sudo findmnt --verify` |
| systemd unit | `systemd-analyze verify /etc/systemd/system/app.service` |

### Special files have special editors

- **sudoers**: always use `sudo visudo` (or `sudo visudo -f /etc/sudoers.d/file`). It checks the syntax before saving. A broken sudoers file can lock everyone out of `sudo`.
- **crontab**: use `crontab -e`, not a text editor on the spool file.
- **systemd units**: use `sudo systemctl edit <service>` to create an override (Chapter 09).

### sudoedit

`sudoedit /etc/hosts` (same as `sudo -e`) copies the file to a temporary location, opens it in your editor as your own user, and writes it back as root when you save. This is safer than running an editor as root.

Choose your default editor:

```bash
export EDITOR=nano        # add to ~/.bashrc to make it permanent
sudo update-alternatives --config editor    # system default on Ubuntu
```

## Lab: Edit, break, and recover

```bash
sudo apt install -y nginx          # on Red Hat family: sudo dnf install -y nginx
sudo cp /etc/nginx/nginx.conf ~/nginx.conf.backup
sudo sed -i 's/worker_connections 768;/worker_connections 768/' /etc/nginx/nginx.conf
sudo nginx -t
```

The `sed` command removes the semicolon after `worker_connections 768`. On Red Hat family systems the default value is `1024`, so change `768` to `1024` in both places of the command.

Output (example, the line number depends on your distribution):

```text
nginx: [emerg] unexpected "}" in /etc/nginx/nginx.conf:10
nginx: configuration file /etc/nginx/nginx.conf test failed
```

The error points at the closing `}`, a few lines **after** the real mistake, because that is where nginx first notices the directive never ended. This is common: when an error line looks correct, check the lines above it.

Find the line you broke and fix it:

```bash
grep -n worker_connections /etc/nginx/nginx.conf
```

Output (example):

```text
8:	worker_connections 768
```

```bash
sudo nano +8 /etc/nginx/nginx.conf      # add the ; back at the end of the line
sudo nginx -t
```

Or restore the backup:

```bash
sudo cp ~/nginx.conf.backup /etc/nginx/nginx.conf
sudo nginx -t
```

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Stuck in vim | You are in Insert mode or a partial command. | `Esc`, `Esc`, `:q!`, `Enter`. |
| `E212: Can't open file for writing` in vim | Editing a root-owned file without sudo. | `:q!`, then reopen with `sudoedit` or `sudo vim`. |
| Service fails after an edit | Syntax error. | Run the service's test command. Restore the backup. |
| Windows line endings (`^M`) break a script | File was edited on Windows. | `sed -i 's/\r$//' script.sh` or `dos2unix script.sh`. |

## Next

[06. Users, Groups, and sudo](../06-users-groups-and-sudo/README.md)
