# 02. Lab Setup

You learn Linux by typing commands, breaking things, and fixing them. This chapter gives you a safe place to do that. Pick one option and move on. You can add a cloud VM later when you reach Chapters 19 to 21.

## What you will learn

- Four ways to get a practice Linux machine, and when to use each one
- How to prepare Windows so you can connect to cloud servers with SSH
- How to reset your lab when you break it

## Choose a lab

| Option | Best for | systemd works? | Cost |
|---|---|---|---|
| WSL 2 on Windows | Daily practice on a Windows laptop | Yes (Ubuntu 24.04 enables it by default) | Free |
| Multipass (Windows, macOS, Linux) | A real Ubuntu VM on your laptop | Yes | Free |
| Docker container | Quick throwaway shell | No, services and `systemctl` do not work | Free |
| Cloud VM (Azure, AWS, GCP) | Everything in this repo, including disks and networking | Yes | Small hourly cost, free tiers exist |

Chapters 01 to 11 and 16 work in any option. Chapters 12, 13, 15, and 17 to 24 need a real VM (Multipass or cloud).

## Option A: WSL 2 on Windows

Open **PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu-24.04
```

Restart when asked. After the restart, Ubuntu opens and asks you to create a Linux username and password. This password is what `sudo` will ask for.

Useful WSL commands (run in PowerShell):

```powershell
wsl --list --verbose        # show installed distros and their state
wsl -d Ubuntu-24.04         # open a shell in that distro
wsl --shutdown              # stop all distros (fixes most WSL oddities)
wsl --unregister Ubuntu-24.04   # delete the distro completely (lab reset)
```

Inside Ubuntu, confirm systemd is running:

```bash
ps -p 1 -o comm=
```

Output:

```text
systemd
```

If it shows `init` instead, add this to `/etc/wsl.conf` and run `wsl --shutdown` from PowerShell:

```ini
[boot]
systemd=true
```

Your Windows drives are available under `/mnt/c`, `/mnt/d`, and so on. Keep lab files in your Linux home directory (`~`) because it is much faster than `/mnt/c`.

## Option B: Multipass (a real VM on your laptop)

Install Multipass from the Canonical website, then:

```bash
multipass launch 24.04 --name lab --cpus 2 --memory 2G --disk 20G
multipass shell lab
```

Output (example):

```text
Launched: lab
ubuntu@lab:~$
```

Lab management:

```bash
multipass list                 # show VMs and their IPs
multipass stop lab             # stop
multipass start lab            # start
multipass delete lab && multipass purge   # delete permanently
```

Multipass VMs behave like cloud VMs: they use cloud-init, have a real disk, and run systemd.

## Option C: Docker container (fastest, most limited)

```bash
docker run -it --rm --name lab ubuntu:24.04 bash
```

You are root inside a minimal Ubuntu. Install the basics first:

```bash
apt update && apt install -y sudo vim nano less curl iproute2 procps
```

`--rm` deletes the container when you exit, which is a clean reset every time. `systemctl` does not work in a normal container, so skip service labs here.

## Option D: A small cloud VM

Follow the create steps in:

- [19. Linux on Azure](../19-linux-on-azure/README.md)
- [20. Linux on AWS](../20-linux-on-aws/README.md)
- [21. Linux on Google Cloud](../21-linux-on-gcp/README.md)

Two rules for cloud labs:

1. Allow SSH only from **your own public IP**, never from `0.0.0.0/0` (the whole internet).
2. Delete the lab when you finish. A forgotten VM keeps costing money.

Find your public IP from any terminal:

```bash
curl -s https://ifconfig.me
```

## Prepare Windows for SSH

Windows 10 and 11 include the OpenSSH client. Check in PowerShell:

```powershell
ssh -V
```

Output (example):

```text
OpenSSH_for_Windows_9.5p1, LibreSSL 3.8.2
```

Create an SSH key once, and use it for every cloud VM:

```powershell
ssh-keygen -t ed25519 -C "your-name-laptop"
```

Press Enter to accept the default location (`C:\Users\<you>\.ssh\id_ed25519`). Set a passphrase. The file ending in `.pub` is your **public key**. You give that to cloud providers. The other file is your **private key**. Never share it.

Chapter [14. SSH](../14-ssh/README.md) covers keys, config files, and troubleshooting in depth.

> **Git Bash** is also a good choice on Windows. It gives you a Bash shell with the same `ssh`, `scp`, `ls`, and `grep` commands you use on the server.

## Lab: Break and reset

The point of a lab is that you can break it. Try this in a container or a throwaway VM, **not** on a server you care about:

```bash
sudo rm /usr/bin/nano
nano test.txt
```

Output:

```text
bash: /usr/bin/nano: No such file or directory
```

Fix it by reinstalling the package:

```bash
sudo apt install --reinstall -y nano
nano --version
```

You just practised the most common repair pattern in Linux: identify what is missing, and reinstall the package that owns it.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| WSL: `Please enable the Virtual Machine Platform` | Virtualisation is off. | Enable virtualisation in BIOS/UEFI, then run `wsl --install` again. |
| WSL: `systemctl` says `System has not been booted with systemd` | systemd not enabled. | Add `systemd=true` to `/etc/wsl.conf`, run `wsl --shutdown`. |
| Docker: `systemctl: command not found` or fails | Containers do not run systemd. | Use WSL, Multipass, or a cloud VM for service labs. |
| `ssh: connect to host ... port 22: Connection timed out` | Firewall or cloud network rule blocks port 22. | See [22. Troubleshooting](../22-troubleshooting/README.md#cannot-connect-with-ssh). |

## Next

[03. Files and Navigation](../03-files-and-navigation/README.md)
