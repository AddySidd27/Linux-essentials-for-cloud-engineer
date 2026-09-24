# 08. Package Management

Software on Linux is installed from **packages** that come from **repositories**. The package manager downloads packages, resolves dependencies, verifies signatures, and keeps track of what is installed. Patching servers, the most frequent operations task, is package management.

## What you will learn

- `apt` (Ubuntu/Debian) and `dnf` (RHEL/Rocky/Amazon Linux) side by side
- Searching, installing, updating, and removing packages
- Security updates, automatic updates, and version pinning
- Adding third-party repositories safely
- Finding which package owns a file

## Side-by-side reference

| Task | Ubuntu / Debian | RHEL / Rocky / Amazon Linux 2023 |
|---|---|---|
| Refresh package lists | `sudo apt update` | `sudo dnf makecache` (usually automatic) |
| Search | `apt search nginx` | `dnf search nginx` |
| Show details | `apt show nginx` | `dnf info nginx` |
| Install | `sudo apt install -y nginx` | `sudo dnf install -y nginx` |
| Remove | `sudo apt remove nginx` | `sudo dnf remove nginx` |
| Remove with config | `sudo apt purge nginx` | (configs removed if unchanged) |
| List available updates | `apt list --upgradable` | `dnf check-update` |
| Apply all updates | `sudo apt upgrade -y` | `sudo dnf upgrade -y` |
| List installed | `apt list --installed` | `dnf list installed` |
| Which package owns a file | `dpkg -S /usr/sbin/nginx` | `rpm -qf /usr/sbin/nginx` |
| Files in a package | `dpkg -L nginx` | `rpm -ql nginx` |
| Which package provides a command | `apt-file search bin/dig` (install `apt-file`) | `dnf provides '*/bin/dig'` |
| Remove unused dependencies | `sudo apt autoremove` | `sudo dnf autoremove` |
| History | `/var/log/apt/history.log` | `sudo dnf history` |

The low-level tools are `dpkg` (Debian) and `rpm` (Red Hat). You rarely use them to install, but they are the fastest way to query what is on the system.

## apt in practice (Ubuntu)

**1. Refresh, then install.**

```bash
sudo apt update
sudo apt install -y nginx
```

Output of `apt update` (example):

```text
Hit:1 http://azure.archive.ubuntu.com/ubuntu noble InRelease
Get:2 http://azure.archive.ubuntu.com/ubuntu noble-updates InRelease [126 kB]
Get:3 http://azure.archive.ubuntu.com/ubuntu noble-security InRelease [126 kB]
Fetched 1,845 kB in 2s (923 kB/s)
14 packages can be upgraded. Run 'apt list --upgradable' to see them.
```

Notice the mirror name: Azure and AWS images point to a mirror inside the cloud, which is fast and free of internet egress charges.

**2. Install a specific version.**

```bash
apt list -a nginx
sudo apt install -y nginx=1.24.0-2ubuntu7
```

**3. Prevent a package from being upgraded.**

```bash
sudo apt-mark hold nginx
apt-mark showhold
sudo apt-mark unhold nginx
```

**4. Check where repositories are defined.**

Ubuntu 24.04 uses the deb822 format in `/etc/apt/sources.list.d/ubuntu.sources`. Older releases use `/etc/apt/sources.list`.

```bash
cat /etc/apt/sources.list.d/ubuntu.sources
```

## dnf in practice (RHEL, Rocky, Amazon Linux 2023)

```bash
sudo dnf install -y nginx
sudo dnf check-update
sudo dnf upgrade -y
sudo dnf history
sudo dnf history undo 12       # roll back transaction 12
```

Output of `dnf history` (example):

```text
ID | Command line             | Date and time    | Action(s)      | Altered
---------------------------------------------------------------------------
13 | upgrade -y               | 2026-09-23 10:10 | Upgrade        |    8
12 | install -y nginx         | 2026-09-23 09:55 | Install        |    5
```

Repositories are defined in `/etc/yum.repos.d/*.repo`:

```bash
dnf repolist
```

Extra packages on Rocky/Alma/RHEL often come from **EPEL**:

```bash
sudo dnf install -y epel-release       # Rocky, AlmaLinux
```

> Amazon Linux 2023 does not support EPEL. Use the packages in the Amazon Linux repositories, or install software from the vendor.

## Security updates

**Ubuntu: see only security updates**

```bash
apt list --upgradable 2>/dev/null | grep -- -security
```

**Red Hat family:**

```bash
sudo dnf updateinfo list --security
sudo dnf upgrade --security -y
```

Output of `updateinfo` (example):

```text
RLSA-2026:1234 Important/Sec. openssl-libs-3.0.7-28.el9.x86_64
RLSA-2026:1250 Moderate/Sec.  curl-7.76.1-30.el9.x86_64
```

### Is a reboot needed?

A kernel or core library update takes effect only after a reboot or a service restart.

```bash
# Ubuntu
ls /var/run/reboot-required && cat /var/run/reboot-required.pkgs

# Red Hat family (needs dnf-utils / yum-utils)
sudo dnf install -y dnf-utils
needs-restarting -r
```

Output (Ubuntu example):

```text
/var/run/reboot-required
linux-image-6.8.0-1016-azure
```

Compare the running kernel with the newest installed one:

```bash
uname -r
ls /boot/vmlinuz-*
```

## Automatic updates

**Ubuntu: unattended-upgrades** (installed on cloud images)

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
cat /etc/apt/apt.conf.d/20auto-upgrades
```

Output:

```text
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```

By default only security updates are installed automatically. Automatic reboots are off. Settings are in `/etc/apt/apt.conf.d/50unattended-upgrades`. Logs are in `/var/log/unattended-upgrades/`.

**Red Hat family: dnf-automatic**

```bash
sudo dnf install -y dnf-automatic
sudo sed -i 's/^upgrade_type = .*/upgrade_type = security/; s/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf
sudo systemctl enable --now dnf-automatic.timer
systemctl list-timers dnf-automatic.timer
```

> In production, automatic updates are a decision, not a default. Many teams patch in scheduled windows through a central tool (Azure Update Manager, AWS Systems Manager Patch Manager) so they control reboots. See [23. Operations Runbooks](../23-operations-runbooks/README.md#patch-a-server).

## Adding a third-party repository safely

Vendors such as Docker, Microsoft, and HashiCorp publish their own repositories. The safe pattern is: download the vendor's signing key into its own file, and tie the repository to that key only.

Example: the Azure CLI on Ubuntu:

```bash
sudo apt install -y ca-certificates curl gnupg
sudo install -d -m 0755 /etc/apt/keyrings
curl -sLS https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
  | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt update
sudo apt install -y azure-cli
```

Always follow the vendor's current documentation for the exact URLs. Avoid `curl ... | sudo bash` from unknown sources: it runs whatever the server sends, as root.

## Other ways software arrives

| Method | Example | Notes |
|---|---|---|
| Snap (Ubuntu) | `sudo snap install amazon-ssm-agent --classic` | Self-updating, isolated. Some cloud agents use it. |
| Language package managers | `pip`, `npm` | Use virtual environments. Do not `sudo pip install` into the system Python. |
| Static binaries | Terraform, kubectl | Place in `/usr/local/bin`, check checksums. |
| Containers | Docker, Podman | Application and dependencies packaged together. |

## Lab: Patch a server and prove it

```bash
# 1. Record the state before patching
uname -r > ~/before-kernel.txt
apt list --upgradable 2>/dev/null | tee ~/before-updates.txt | wc -l

# 2. Apply updates
sudo apt update && sudo apt upgrade -y

# 3. Check whether a reboot is required
[ -f /var/run/reboot-required ] && echo "Reboot required" || echo "No reboot required"

# 4. Reboot if required, reconnect, and compare
sudo reboot
# (reconnect)
echo "Before: $(cat ~/before-kernel.txt)  After: $(uname -r)"
grep -A3 "$(date +%F)" /var/log/apt/history.log | head -20
```

Output of the comparison (example):

```text
Before: 6.8.0-1015-azure  After: 6.8.0-1016-azure
```

On Red Hat family systems, replace step 2 with `sudo dnf upgrade -y` and step 3 with `needs-restarting -r`.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `Could not get lock /var/lib/dpkg/lock-frontend` | Another apt process is running, often unattended-upgrades on a new VM. | Wait: `while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done`. Do not delete lock files. |
| `dpkg was interrupted, you must manually run 'sudo dpkg --configure -a'` | An install was stopped midway. | Run that command, then `sudo apt -f install`. |
| `Unable to locate package` | Lists not refreshed, wrong name, or repo missing. | `sudo apt update`, `apt search`. |
| `NO_PUBKEY` / GPG error | Repository signing key missing or expired. | Re-add the key from the vendor's documentation. |
| `Temporary failure resolving` / timeouts | DNS or outbound network blocked. | Chapter 13 and the cloud firewall or NAT settings. |
| `No space left on device` during upgrade | `/boot` or `/` full. | `sudo apt autoremove` removes old kernels. Check `df -h`. |

## Next

[09. Processes and Services](../09-processes-and-services/README.md)
