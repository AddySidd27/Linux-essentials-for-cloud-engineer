# 15. Security Hardening

A new cloud VM is reachable from the internet within minutes of being created, and automated scanners will find it. Hardening means reducing what an attacker can reach and making sure you notice when something goes wrong. This chapter is a practical baseline you can apply to any new server.

## What you will learn

- A baseline checklist for new Linux servers
- Reducing exposed services
- Brute-force protection with fail2ban
- SELinux (Red Hat family) and AppArmor (Ubuntu): what they do and how to troubleshoot them
- Auditing with `auditd` and scanning with Lynis
- Handling secrets on a server

## Baseline checklist

| # | Control | How | Chapter |
|---|---|---|---|
| 1 | Patch now and keep patching | `apt upgrade` / `dnf upgrade`, automatic security updates or a patch schedule | 08 |
| 2 | Key-only SSH, no root login | `PasswordAuthentication no`, `PermitRootLogin no` | 14 |
| 3 | Restrict who can reach SSH | Cloud rule from known IPs or use Bastion / Session Manager / IAP | 14, 19-21 |
| 4 | Named accounts, least privilege | One account per person, limited sudo rules | 06 |
| 5 | Remove or disable unused services | `ss -tulpn`, `systemctl disable --now` | this chapter |
| 6 | Host firewall as a second layer | `ufw` / `firewalld` | 13 |
| 7 | Keep SELinux / AppArmor enforcing | `getenforce`, `aa-status` | this chapter |
| 8 | Accurate time | `chrony` / `systemd-timesyncd` | this chapter |
| 9 | Central logs and alerts | Cloud monitoring agent | 11 |
| 10 | Encrypted disks and backups | Cloud disk encryption (on by default), snapshots | 19-21, 23 |

## Reduce what is exposed

List everything listening on the network:

```bash
sudo ss -tulpn
```

For each port, ask: does this server need it, and does it need to listen on all interfaces? Disable what is not needed:

```bash
systemctl list-unit-files --type=service --state=enabled
sudo systemctl disable --now cups        # example: printing service on a server
```

Remove packages you do not use:

```bash
sudo apt purge telnet ftp        # Ubuntu
sudo dnf remove telnet ftp       # Red Hat family
```

## Brute-force protection with fail2ban

fail2ban reads logs and temporarily blocks IP addresses that fail to log in too many times.

```bash
sudo apt install -y fail2ban           # Red Hat family: sudo dnf install -y epel-release && sudo dnf install -y fail2ban
sudo tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
EOF
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

Output (example):

```text
Status for the jail: sshd
|- Filter
|  |- Currently failed: 2
|  |- Total failed:     37
|  `- Journal matches:  _SYSTEMD_UNIT=sshd.service + _COMM=sshd
`- Actions
   |- Currently banned: 3
   |- Total banned:     9
   `- Banned IP list:   198.51.100.7 203.0.113.44 192.0.2.201
```

Unban an address (for example, a colleague who mistyped):

```bash
sudo fail2ban-client set sshd unbanip 203.0.113.44
```

> fail2ban is a helper, not a replacement for restricting port 22 in the cloud rules. If only your IP can reach SSH, brute-force attempts never arrive.

## Mandatory access control: SELinux and AppArmor

Normal permissions (Chapter 07) control what a **user** can do. SELinux and AppArmor also control what a **program** can do, even when it runs as root. If an attacker takes over nginx, nginx still cannot read `/etc/shadow`.

| | SELinux | AppArmor |
|---|---|---|
| Used by | RHEL, Rocky, AlmaLinux, Amazon Linux 2023 | Ubuntu, Debian, SUSE |
| Status | `getenforce`, `sestatus` | `sudo aa-status` |
| Denials logged in | `/var/log/audit/audit.log` | `journalctl -k`, `/var/log/syslog` |

> Amazon Linux 2023 ships with SELinux in **permissive** mode: it logs what it would block but does not block. RHEL and Rocky ship **enforcing**.

### SELinux in practice

Every file and process has a label (context). A process may only touch files with labels its policy allows.

```bash
getenforce
ls -Z /var/www/html/index.html
```

Output (example):

```text
Enforcing
unconfined_u:object_r:httpd_sys_content_t:s0 /var/www/html/index.html
```

`httpd_sys_content_t` is the label nginx and Apache are allowed to read.

**The most common SELinux problem:** you create content somewhere else and move it into place. `mv` keeps the old label, so the web server gets "Permission denied" even though normal permissions are fine.

```bash
echo "hi" > ~/index.html
sudo mv ~/index.html /var/www/html/index.html
ls -Z /var/www/html/index.html        # shows user_home_t, the wrong label
sudo ausearch -m avc -ts recent       # shows the denial
sudo restorecon -v /var/www/html/index.html
```

Output of `restorecon`:

```text
Relabeled /var/www/html/index.html from unconfined_u:object_r:user_home_t:s0 to unconfined_u:object_r:httpd_sys_content_t:s0
```

Other common fixes:

```bash
# Serve content from a non-standard directory
sudo semanage fcontext -a -t httpd_sys_content_t "/srv/site(/.*)?"
sudo restorecon -Rv /srv/site

# Allow nginx to connect to a backend application (reverse proxy)
sudo setsebool -P httpd_can_network_connect on

# Allow a service to listen on a non-standard port
sudo semanage port -a -t http_port_t -p tcp 8081
```

`semanage` comes from `policycoreutils-python-utils`. Get a readable explanation of a denial with `sudo sealert -a /var/log/audit/audit.log` (package `setroubleshoot-server`).

> Do not "fix" SELinux problems with `setenforce 0`. That turns protection off for everything. Find the label, boolean, or port that is wrong and fix only that.

### AppArmor in practice

```bash
sudo aa-status | head
sudo journalctl -k | grep -i 'apparmor="DENIED"' | tail -5
```

AppArmor profiles live in `/etc/apparmor.d/`. If a profile blocks a legitimate path, the usual fix is a local override in `/etc/apparmor.d/local/<profile>`, then `sudo apparmor_parser -r /etc/apparmor.d/<profile>`.

## Time synchronisation

Wrong time breaks TLS certificates, Kerberos and Microsoft Entra ID logins, and makes logs from different servers impossible to line up.

```bash
timedatectl
chronyc tracking            # if chrony is used (Red Hat family, Amazon Linux, Ubuntu on Azure/AWS)
```

Output of `timedatectl` (example):

```text
               Local time: Tue 2026-09-23 12:05:10 UTC
System clock synchronized: yes
              NTP service: active
```

Cloud VMs sync with the provider's time source (Azure host via PTP, AWS `169.254.169.123`, Google `metadata.google.internal`). Keep servers in UTC. Convert when you read the logs.

## Auditing

`auditd` records security-relevant events: who changed a file, who ran a command as root.

```bash
sudo apt install -y auditd            # Red Hat family: installed by default
sudo auditctl -w /etc/ssh/sshd_config -p wa -k sshd-config
sudo auditctl -w /etc/sudoers -p wa -k sudoers
```

After someone edits the file:

```bash
sudo ausearch -k sshd-config -i | tail -20
```

The output includes the user (`auid`, the original login user even after `sudo`), the time, and the program used. Make rules permanent in `/etc/audit/rules.d/hardening.rules`.

## Scan with Lynis

Lynis checks hundreds of settings and gives you a prioritised list.

```bash
sudo apt install -y lynis              # Red Hat family: EPEL, or download from the vendor
sudo lynis audit system --quick
```

Output (end of report, example):

```text
  Hardening index : 64 [############        ]
  Tests performed : 262
  ...
  Suggestions (34):
  * Set a password on GRUB boot loader [BOOT-5122]
  * Consider hardening SSH configuration [SSH-7408]
```

Treat the suggestions as a to-do list to review, not a list to apply blindly. For formal baselines, organisations use the **CIS Benchmarks**; cloud marketplaces offer CIS-hardened images.

## Secrets on a server

- Do not put passwords or keys in scripts, crontabs, or Git.
- Prefer the cloud's identity for the VM: **managed identity** (Azure), **instance profile / IAM role** (AWS), **service account** (Google Cloud). The VM gets short-lived tokens from the metadata service and never stores a key. See [18. cloud-init and Metadata](../18-cloud-init-and-metadata/README.md).
- Store application secrets in Azure Key Vault, AWS Secrets Manager, or Google Secret Manager.
- If a secret must be a file, make it `600` and owned by the service account.
- Check shell history for pasted secrets: `history | grep -i pass`. Remove lines with `history -d <n>`.

## Lab: Harden a fresh VM and measure it

1. Run `sudo lynis audit system --quick` and note the hardening index.
2. Apply: updates, SSH hardening (Chapter 14), host firewall with only SSH and HTTP, fail2ban, disable one unused service, time sync check.
3. On a Rocky or RHEL VM: move a file into `/var/www/html` from your home directory, observe the SELinux denial, and fix it with `restorecon`.
4. Add an audit rule on `/etc/ssh/sshd_config`, edit the file, and find your change with `ausearch`.
5. Run Lynis again and compare the index.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Web server 403 on Rocky/RHEL with correct permissions | Wrong SELinux label. | `ls -Z`, `restorecon -Rv`. |
| nginx reverse proxy returns 502 on Rocky/RHEL | SELinux blocks outbound connections from httpd. | `setsebool -P httpd_can_network_connect on`. |
| Locked out after enabling a firewall or `AllowGroups` | SSH not allowed. | Cloud console or run-command, then fix. |
| fail2ban banned your own IP | Too many failed attempts. | `fail2ban-client set sshd unbanip <ip>`. Add `ignoreip` in `jail.local`. |
| TLS errors "certificate not yet valid" | Clock wrong. | `timedatectl`, restart `chronyd`. |

## Next

[16. Bash Scripting](../16-bash-scripting/README.md)
