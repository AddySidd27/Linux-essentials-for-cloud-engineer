# 01. Linux Fundamentals

Almost every virtual machine you create in Azure, AWS, or Google Cloud that is not running Windows is running Linux. Containers, Kubernetes nodes, and most managed services also run on Linux underneath. This chapter explains what you are looking at when you first connect to a Linux server.

## What you will learn

- What Linux is made of: kernel, shell, and distribution
- Which distributions you will meet in the cloud and how they differ
- How to identify an unknown server in under a minute
- How to find help for any command without leaving the terminal

## How Linux is put together

| Part | What it does | Example |
|---|---|---|
| Kernel | Talks to hardware. Manages CPU, memory, disks, and network. | `6.8.0-1015-azure` |
| Init system | First process started by the kernel. Starts and supervises all services. | `systemd` |
| Shell | Program that reads the commands you type and runs them. | `bash` |
| User-space tools | The commands you use every day. | `ls`, `cp`, `grep`, `ssh` |
| Package manager | Installs, updates, and removes software. | `apt`, `dnf` |

A **distribution** (distro) is the kernel plus a chosen set of tools, a package manager, default settings, and a support lifecycle. Ubuntu, Red Hat Enterprise Linux (RHEL), and Amazon Linux are distributions.

## Distributions you will see in the cloud

| Family | Distributions | Package manager | Default cloud user |
|---|---|---|---|
| Debian | Ubuntu, Debian | `apt` | `azureuser` (Azure), `ubuntu` (AWS) |
| Red Hat | RHEL, Rocky Linux, AlmaLinux, Oracle Linux | `dnf` | `azureuser` (Azure), `ec2-user` (AWS) |
| Amazon | Amazon Linux 2023 | `dnf` | `ec2-user` |
| SUSE | SLES | `zypper` | `azureuser` (Azure), `ec2-user` (AWS) |

This repository uses **Ubuntu 24.04 LTS** as the main example. Where the Red Hat family works differently, both commands are shown. Amazon Linux 2023 behaves like the Red Hat family for almost everything in this guide.

> **LTS** means Long Term Support. Ubuntu LTS releases receive security updates for five years. Use LTS releases for servers.

## Identify a server you have never seen

When you are handed access to a server, run these commands before you change anything.

**1. Which distribution and version is this?**

```bash
cat /etc/os-release
```

Output (example):

```text
PRETTY_NAME="Ubuntu 24.04.1 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
ID=ubuntu
ID_LIKE=debian
```

`ID_LIKE=debian` tells you to use `apt`. On Rocky Linux you would see `ID_LIKE="rhel centos fedora"`, which means `dnf`.

**2. Which kernel is running?**

```bash
uname -r
```

Output (example):

```text
6.8.0-1015-azure
```

The `-azure` suffix means the cloud-tuned kernel. On AWS you would see `-aws`.

**3. Which CPU architecture?**

```bash
uname -m
```

Output (example):

```text
x86_64
```

`x86_64` is Intel or AMD. `aarch64` is ARM (AWS Graviton, Azure Cobalt/Ampere). This matters when you download software, because an ARM server cannot run an x86 binary.

**4. Who am I, and can I use sudo?**

```bash
whoami
id
sudo -l
```

Output (example):

```text
azureuser
uid=1000(azureuser) gid=1000(azureuser) groups=1000(azureuser),27(sudo)
User azureuser may run the following commands on web01:
    (ALL : ALL) NOPASSWD: ALL
```

Being in the `sudo` group (Ubuntu) or `wheel` group (Red Hat) means you can run administrative commands.

**5. What is this machine called, and how long has it been running?**

```bash
hostnamectl
uptime
```

Output (example):

```text
 Static hostname: web01
  Virtualization: microsoft
Operating System: Ubuntu 24.04.1 LTS
          Kernel: Linux 6.8.0-1015-azure
    Architecture: x86-64
 10:42:11 up 12 days,  3:07,  1 user,  load average: 0.08, 0.12, 0.10
```

`Virtualization: microsoft` means Azure (Hyper-V). AWS shows `amazon` or `kvm`.

**6. How much CPU, memory, and disk does it have?**

```bash
nproc
free -h
df -h /
```

Output (example):

```text
2
               total        used        free      shared  buff/cache   available
Mem:           7.7Gi       1.1Gi       5.2Gi       4.0Mi       1.7Gi       6.4Gi
Swap:             0B          0B          0B
Filesystem      Size  Used Avail Use% Mounted on
/dev/root        29G  3.1G   26G  11% /
```

**7. What is its IP address?**

```bash
ip -brief address
```

Output (example):

```text
lo               UNKNOWN        127.0.0.1/8 ::1/128
eth0             UP             10.0.1.4/24 fe80::20d:3aff:fe12:3456/64
```

Cloud VMs usually show only the **private** IP here. The public IP belongs to the cloud network, not to the VM's network card.

## Getting help

You do not need to memorise options. Every tool documents itself.

| Command | Use it for |
|---|---|
| `man ls` | Full manual page. Press `/` to search, `q` to quit. |
| `ls --help` | Short summary of options. |
| `man -k partition` | Search all manual pages for a word. |
| `type ls` | Shows whether a command is a program, alias, or shell builtin. |
| `which python3` | Shows which file runs when you type a command. |

Example:

```bash
man -k "disk usage"
```

Output (example):

```text
df (1)               - report file system space usage
du (1)               - estimate file space usage
```

> Minimal cloud images sometimes remove manual pages to save space. On Ubuntu, `sudo unminimize` restores them.

## How the shell reads a command

```text
sudo  systemctl  restart  nginx
 |       |          |       |
 |       |          |       +-- argument (what to act on)
 |       |          +---------- subcommand (what to do)
 |       +--------------------- the program
 +----------------------------- run it as root
```

- Options start with `-` (short, like `-l`) or `--` (long, like `--all`).
- Linux is **case-sensitive**. `File.txt` and `file.txt` are two different files.
- There is no recycle bin. A deleted file is gone.

## Lab: Build a server profile

Connect to any Linux machine (see [Chapter 02](../02-lab-setup/README.md) if you do not have one) and create a short report:

```bash
{
  echo "Host:     $(hostname)"
  echo "OS:       $(. /etc/os-release && echo "$PRETTY_NAME")"
  echo "Kernel:   $(uname -r)"
  echo "Arch:     $(uname -m)"
  echo "CPUs:     $(nproc)"
  echo "Memory:   $(free -h | awk '/Mem:/ {print $2}')"
  echo "Root disk: $(df -h / | awk 'NR==2 {print $2 " total, " $5 " used"}')"
  echo "IP:       $(hostname -I)"
} > ~/server-profile.txt

cat ~/server-profile.txt
```

Output (example):

```text
Host:     web01
OS:       Ubuntu 24.04.1 LTS
Kernel:   6.8.0-1015-azure
Arch:     x86_64
CPUs:     2
Memory:   7.7Gi
Root disk: 29G total, 11% used
IP:       10.0.1.4
```

**Check yourself:** Which package manager would you use on this server? Which default user would AWS give you for the same Ubuntu image?

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `command not found` | The tool is not installed, or you mistyped it. | Check spelling. Install the package (Chapter 08). |
| `Permission denied` | The action needs root. | Retry with `sudo`, if your role allows it. |
| `man: command not found` or no manual entry | Minimal image. | Use `--help`, or install `man-db`. |

## Next

[02. Lab Setup](../02-lab-setup/README.md)
