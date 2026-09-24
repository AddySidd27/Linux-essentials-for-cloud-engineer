# 07. Permissions and Ownership

"Permission denied" is one of the most common errors you will fix. It usually means the wrong user, the wrong group, or the wrong mode on a file or one of its parent directories. This chapter teaches you to read and fix all three.

## What you will learn

- Reading permission strings and numeric modes
- Changing permissions with `chmod` and ownership with `chown`
- How directory permissions differ from file permissions
- `umask`, special bits (setgid, sticky), and ACLs
- A step-by-step method for fixing "Permission denied"

## Reading permissions

```bash
ls -l /var/www/html/index.html
```

Output (example):

```text
-rw-r--r-- 1 www-data www-data 612 Sep 23 10:00 /var/www/html/index.html
```

```text
-   rw-   r--   r--
|    |     |     |
|    |     |     +-- others (everyone else)
|    |     +-------- group (www-data)
|    +-------------- owner (www-data)
+------------------- type: - file, d directory, l link
```

| Letter | On a file | On a directory |
|---|---|---|
| `r` read | Read the contents | List the names inside |
| `w` write | Change the contents | Create, delete, rename entries inside |
| `x` execute | Run it as a program | Enter it (`cd`) and reach files inside |

> To open `/var/www/html/index.html`, a user needs `x` on `/`, `/var`, `/var/www`, and `/var/www/html`, **and** `r` on the file. One missing `x` on a parent directory causes "Permission denied" even if the file itself is readable.

## Numeric (octal) mode

Each permission has a value: `r=4`, `w=2`, `x=1`. Add them for each of owner, group, and others.

| Mode | Symbolic | Typical use |
|---|---|---|
| `644` | `rw-r--r--` | Normal files, web content, most configs |
| `600` | `rw-------` | Private files: SSH private keys, secrets |
| `640` | `rw-r-----` | Config readable by a service group |
| `755` | `rwxr-xr-x` | Directories, scripts, programs |
| `750` | `rwxr-x---` | Directories only a group should enter |
| `700` | `rwx------` | `~/.ssh`, private directories |
| `400` | `r--------` | Cloud key files (`.pem`) |

## chmod

```bash
chmod 640 app.conf             # numeric
chmod u+x deploy.sh            # add execute for the owner
chmod g-w,o-rwx secrets.env    # remove write for group, everything for others
chmod -R g+rX /srv/shared      # recursive; capital X = execute only on directories
```

`u` = owner (user), `g` = group, `o` = others, `a` = all.

## chown

```bash
sudo chown www-data:www-data /var/www/html/index.html   # owner and group
sudo chown -R myapp:myapp /var/lib/myapp                # recursive
sudo chgrp webadmins /srv/shared                        # group only
```

## Inspect the full path with namei

`namei -l` shows the permissions of every directory on the way to a file. It is the fastest way to find the missing `x`.

```bash
namei -l /var/www/html/index.html
```

Output (example):

```text
f: /var/www/html/index.html
drwxr-xr-x root     root     /
drwxr-xr-x root     root     var
drwxr-xr-x root     root     www
drwxr-x--- root     root     html
-rw-r--r-- www-data www-data index.html
```

Here `html` is `drwxr-x---` and owned by `root:root`, so the `www-data` user (nginx) cannot enter it, even though it owns the file.

## umask: default permissions for new files

```bash
umask
```

Output:

```text
0022
```

New files start at `666` and directories at `777`, then the umask bits are removed. With `022`, files become `644` and directories `755`. A umask of `027` gives `640` and `750`, which keeps new files away from other users.

## Special bits

| Bit | Numeric | Effect | Example |
|---|---|---|---|
| setuid | `4000` | Program runs as its owner | `/usr/bin/passwd` (`-rwsr-xr-x`) |
| setgid on a directory | `2000` | New files inherit the directory's group | Shared team folders |
| sticky on a directory | `1000` | Users can delete only their own files | `/tmp` (`drwxrwxrwt`) |

A shared folder for a team:

```bash
sudo mkdir -p /srv/shared
sudo chgrp webadmins /srv/shared
sudo chmod 2775 /srv/shared
ls -ld /srv/shared
```

Output:

```text
drwxrwsr-x 2 root webadmins 4096 Sep 23 11:00 /srv/shared
```

The `s` in the group position is setgid. Every file created inside is owned by the `webadmins` group, so all members can work on it.

Find setuid programs (a normal security audit step):

```bash
sudo find / -xdev -perm -4000 -type f 2>/dev/null
```

## ACLs: permissions for one extra user or group

Standard permissions allow one owner and one group. ACLs let you add more without changing either.

```bash
sudo apt install -y acl                          # Red Hat family: installed by default
sudo setfacl -m u:deploy:rx /var/log/myapp       # give user deploy read and enter
getfacl /var/log/myapp
```

Output (example):

```text
# file: var/log/myapp
# owner: myapp
# group: myapp
user::rwx
user:deploy:r-x
group::r-x
mask::r-x
other::---
```

A `+` at the end of the mode in `ls -l` (`drwxr-x---+`) tells you an ACL exists. Remove it with `setfacl -b`.

## When permissions look right but access still fails

| Cause | How to check |
|---|---|
| SELinux (Red Hat family) blocks it | `getenforce`, `ls -Z`, `sudo ausearch -m avc -ts recent` (Chapter 15) |
| AppArmor (Ubuntu) blocks it | `sudo aa-status`, `sudo journalctl -k \| grep -i apparmor` |
| Filesystem mounted read-only | `findmnt -no OPTIONS /path` shows `ro` |
| Filesystem mounted with `noexec` | Scripts on it cannot run. `findmnt -no OPTIONS /tmp` |
| Immutable attribute set | `lsattr file` shows `i`. Remove with `sudo chattr -i file` |

## Method: fixing "Permission denied"

1. **Who is trying?** The user running the process, not you. `ps -o user= -p <pid>` or check `User=` in the service file.
2. **What exactly is denied?** Read the error or log for the full path.
3. **Check the whole path:** `namei -l /full/path`.
4. **Test as that user:** `sudo -u www-data cat /var/www/html/index.html`.
5. **Fix the smallest thing:** usually a group or one `x` on a directory. Avoid `chmod 777`. It hides the real problem and lets any user change the file.
6. **If it still fails:** check SELinux or AppArmor, mount options, and attributes (table above).

## Lab: Fix a broken website

```bash
sudo apt install -y nginx
echo "<h1>Hello</h1>" | sudo tee /var/www/html/index.html
curl -s localhost
sudo chmod 750 /var/www/html
sudo chown root:root /var/www/html
curl -s localhost | head -3
```

Output of the last command (example):

```text
<html>
<head><title>403 Forbidden</title></head>
<body>
```

Diagnose and fix:

```bash
sudo tail -n 2 /var/log/nginx/error.log
namei -l /var/www/html/index.html
sudo -u www-data cat /var/www/html/index.html
sudo chmod 755 /var/www/html
curl -s localhost
```

Output of the error log (example):

```text
... open() "/var/www/html/index.html" failed (13: Permission denied) ...
```

Final output:

```text
<h1>Hello</h1>
```

Error `13: Permission denied` is the kernel's permission error. `namei` showed the directory without `x` for others, and `sudo -u www-data` confirmed it before you changed anything.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `bash: ./script.sh: Permission denied` | No execute bit, or `noexec` mount. | `chmod u+x script.sh`, or run `bash script.sh`. |
| `WARNING: UNPROTECTED PRIVATE KEY FILE!` | Key file readable by others. | `chmod 600 key` (or `400`). |
| Web server returns 403 | Service user cannot read the file or enter a directory. | `namei -l`, then fix the directory mode or group. |
| `Operation not permitted` even as root | Immutable attribute or read-only mount. | `lsattr`, `findmnt`. |

## Next

[08. Package Management](../08-package-management/README.md)
