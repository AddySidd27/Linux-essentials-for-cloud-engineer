# 06. Users, Groups, and sudo

Every process and every file on Linux belongs to a user. Access control, SSH logins, and the question "who changed this?" all depend on how users and groups are set up. In cloud work you will create admin accounts, service accounts for applications, and grant or remove sudo access.

## What you will learn

- How Linux stores users and groups
- Creating, changing, locking, and deleting users
- Giving a user SSH access with a key
- Granting sudo safely, including limited sudo rules
- Service accounts for applications

## Key ideas

| Term | Meaning |
|---|---|
| UID | Numeric user ID. `0` is root. Normal users usually start at `1000`. |
| GID | Numeric group ID. |
| Primary group | The group that owns new files the user creates. Usually has the same name as the user. |
| Supplementary groups | Extra groups that grant access, for example `sudo`, `docker`, `adm`. |
| root | The superuser. Can do anything. Do not log in as root. Use `sudo`. |
| Service account | A user that runs a program and cannot log in. |

## Where the information lives

```bash
grep azureuser /etc/passwd
```

Output (example):

```text
azureuser:x:1000:1000:Azure User:/home/azureuser:/bin/bash
```

```text
name : x : UID : GID : comment : home directory : login shell
```

The `x` means the password hash is stored in `/etc/shadow`, which only root can read.

| File | Contains |
|---|---|
| `/etc/passwd` | User accounts |
| `/etc/shadow` | Password hashes and expiry settings |
| `/etc/group` | Groups and their members |
| `/etc/sudoers` and `/etc/sudoers.d/` | Who may use sudo, and for what |

Check a user:

```bash
id azureuser
getent passwd azureuser
groups azureuser
```

Output of `id` (example):

```text
uid=1000(azureuser) gid=1000(azureuser) groups=1000(azureuser),4(adm),27(sudo)
```

`getent` also finds users that come from a directory service such as Microsoft Entra ID or LDAP, which `/etc/passwd` does not show.

## Creating users

```bash
sudo useradd -m -s /bin/bash -c "Priya Sharma" priya
sudo passwd priya
```

| Option | Meaning |
|---|---|
| `-m` | Create the home directory |
| `-s /bin/bash` | Login shell |
| `-c` | Comment, usually the full name |
| `-G sudo,adm` | Add to supplementary groups |
| `-u 1500` | Choose the UID |

Ubuntu also has `adduser priya`, an interactive helper that asks for the password and details.

> On cloud VMs, password login over SSH is usually disabled. Users log in with SSH keys. You can skip setting a password unless the user needs it for `sudo`.

## Giving a user SSH access

The user's public key goes into `~/.ssh/authorized_keys` in their home directory, with strict permissions.

```bash
sudo mkdir -p /home/priya/.ssh
echo "ssh-ed25519 AAAAC3Nza... priya@laptop" | sudo tee /home/priya/.ssh/authorized_keys
sudo chown -R priya:priya /home/priya/.ssh
sudo chmod 700 /home/priya/.ssh
sudo chmod 600 /home/priya/.ssh/authorized_keys
```

Test from Priya's machine:

```bash
ssh priya@<server-ip>
```

If the permissions are too open, SSH silently ignores the key and the login fails. See [14. SSH](../14-ssh/README.md).

## Groups

```bash
sudo groupadd webadmins                 # create a group
sudo usermod -aG webadmins priya        # add priya to it
getent group webadmins
```

Output:

```text
webadmins:x:1001:priya
```

> Always use `-aG` (append) with `usermod`. `-G` alone **replaces** all supplementary groups, which can remove a user from `sudo`.

Group changes apply at the next login. The user can log out and in again, or run `newgrp webadmins` in the current shell.

Remove a user from a group:

```bash
sudo gpasswd -d priya webadmins
```

## sudo

`sudo` runs a single command as root and records it in the logs. Users get sudo by being in a group that the sudoers file allows:

| Distribution family | Admin group |
|---|---|
| Ubuntu / Debian | `sudo` |
| RHEL / Rocky / Amazon Linux | `wheel` |

Give full admin rights:

```bash
sudo usermod -aG sudo priya       # Ubuntu
sudo usermod -aG wheel priya      # Red Hat family
```

### Limited sudo rules

Often a person or an automation only needs one or two commands. Create a file in `/etc/sudoers.d/` with `visudo`, which checks syntax before saving:

```bash
sudo visudo -f /etc/sudoers.d/webadmins
```

Content:

```text
# Members of webadmins can manage nginx only
%webadmins ALL=(root) /usr/bin/systemctl restart nginx, /usr/bin/systemctl reload nginx, /usr/bin/systemctl status nginx
```

Test as priya:

```bash
sudo -l
sudo systemctl reload nginx     # allowed
sudo cat /etc/shadow            # refused
```

Output of the refused command (example):

```text
Sorry, user priya is not allowed to execute '/usr/bin/cat /etc/shadow' as root on web01.
```

Rules for sudoers files:

- Always use full paths to commands (`which systemctl`).
- File names in `/etc/sudoers.d/` must not contain a `.` or end with `~`, or they are ignored.
- `NOPASSWD:` skips the password prompt. Use it only for automation accounts that have no password.

Check the whole configuration:

```bash
sudo visudo -c
```

Output:

```text
/etc/sudoers: parsed OK
/etc/sudoers.d/webadmins: parsed OK
```

## Changing and removing users

```bash
sudo usermod -s /bin/zsh priya          # change shell
sudo usermod -l priya.s priya           # rename login
sudo chage -l priya                     # show password expiry settings
sudo chage -M 90 priya                  # password expires every 90 days
```

**Offboarding a person.** Lock first, delete later, so you keep the files until someone reviews them:

```bash
sudo usermod -L priya                        # lock the password
sudo usermod -s /usr/sbin/nologin priya      # block interactive login
sudo mv /home/priya/.ssh/authorized_keys /home/priya/.ssh/authorized_keys.disabled
sudo pkill -u priya                          # end running sessions
```

> Locking the password alone does **not** stop SSH key logins. Removing or disabling `authorized_keys` and setting the shell to `nologin` does.

Delete when approved:

```bash
sudo userdel -r priya     # -r removes the home directory and mail spool
```

Find files the deleted user still owned elsewhere:

```bash
sudo find / -xdev -nouser 2>/dev/null
```

## Service accounts

Applications should run as their own user, never as root. That way a bug in the app cannot change the rest of the system.

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin myapp
sudo mkdir -p /opt/myapp /var/lib/myapp
sudo chown -R myapp:myapp /var/lib/myapp
```

`--system` picks a UID below 1000. The systemd service in [Chapter 09](../09-processes-and-services/README.md) will run as this user.

## Who is logged in, and who was?

```bash
who                  # current sessions
w                    # sessions and what they are running
last -n 10           # recent logins
lastb -n 10          # recent failed logins (needs sudo)
sudo journalctl -u ssh --since "1 hour ago"      # Ubuntu (service is ssh)
sudo journalctl -u sshd --since "1 hour ago"     # Red Hat family (service is sshd)
```

## Lab: Onboard and offboard an engineer

1. Create a user `devops1` with a home directory and bash.
2. Create a group `ops` and add `devops1` to it.
3. Allow the `ops` group to run only `systemctl restart nginx` and `journalctl` with sudo.
4. Add an SSH public key for `devops1` (generate one with `ssh-keygen -t ed25519 -f /tmp/devops1` for the lab).
5. Log in as `devops1` and confirm what sudo allows.
6. Offboard `devops1`: lock, block login, disable the key, end sessions.

```bash
sudo useradd -m -s /bin/bash devops1
sudo groupadd ops
sudo usermod -aG ops devops1
echo '%ops ALL=(root) /usr/bin/systemctl restart nginx, /usr/bin/journalctl' | sudo tee /etc/sudoers.d/ops
sudo chmod 440 /etc/sudoers.d/ops
sudo visudo -c

ssh-keygen -t ed25519 -f /tmp/devops1 -N ""
sudo install -d -m 700 -o devops1 -g devops1 /home/devops1/.ssh
sudo install -m 600 -o devops1 -g devops1 /tmp/devops1.pub /home/devops1/.ssh/authorized_keys

ssh -i /tmp/devops1 devops1@localhost 'sudo -l'
```

Output of the last command (example):

```text
User devops1 may run the following commands on web01:
    (root) /usr/bin/systemctl restart nginx, /usr/bin/journalctl
```

`install -d` creates a directory with the owner and mode in one step. `install -m` copies a file with the owner and mode in one step.

Now offboard and confirm the key no longer works:

```bash
sudo usermod -L -s /usr/sbin/nologin devops1
sudo mv /home/devops1/.ssh/authorized_keys /home/devops1/.ssh/authorized_keys.disabled
ssh -i /tmp/devops1 devops1@localhost
```

Output:

```text
devops1@localhost: Permission denied (publickey).
```

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `user is not in the sudoers file` | User is not in `sudo`/`wheel` and has no sudoers rule. | Add to the group from another admin account, then log in again. |
| New group membership not working | Groups load at login. | Log out and back in, or `newgrp <group>`. |
| `sudo: parse error in /etc/sudoers.d/...` | File was edited without `visudo`. | Fix with `pkexec visudo` if available, or use the cloud recovery tools in Chapters 19 and 20. |
| SSH key login refused for a new user | Wrong owner or permissions on `.ssh`. | `chown -R user:user ~user/.ssh`, `chmod 700` directory, `chmod 600` file. |

## Next

[07. Permissions and Ownership](../07-permissions-and-ownership/README.md)
