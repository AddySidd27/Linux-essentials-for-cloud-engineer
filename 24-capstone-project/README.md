# 24. Capstone Project

Build a production-style Linux web server from nothing, on Azure, AWS, or Google Cloud, using everything in this repository. Then break it in realistic ways and fix it. If you can finish this without looking up the steps, you can create, configure, operate, and troubleshoot Linux servers in the cloud.

## The goal

A small web application, `myapp`, running behind nginx on a hardened Linux VM, with its data on a separate disk, monitored, backed up, and patched, and fully documented.

```text
Internet ──► Cloud firewall (80/443 from anywhere, 22 from your IP only or no SSH at all)
                │
            Linux VM (Ubuntu 24.04 or Rocky 9)
                ├── nginx :80/:443  ──►  myapp :8080 (127.0.0.1 only, systemd, runs as "myapp")
                ├── /data  (separate data disk, LVM, fstab by UUID, nofail)
                ├── host firewall, fail2ban, key-only SSH, SELinux/AppArmor enforcing
                ├── health check timer, disk alert, logrotate, journal limit
                ├── nightly backup to cloud storage using the VM's identity
                └── monitoring agent sending metrics and logs
```

## Requirements

Tick each item and keep the evidence (command output or screenshot).

### Build

- [ ] VM created from the CLI with a cloud-config (Chapter 18). No manual steps to get nginx running.
- [ ] Cloud firewall allows SSH only from your IP (or no inbound SSH, using Bastion / Session Manager / IAP).
- [ ] Hostname, timezone UTC, time synchronised.
- [ ] Named admin user with an ed25519 key. `PasswordAuthentication no`, `PermitRootLogin no`.
- [ ] Fully patched. Automatic security updates or a documented patch schedule.

### Storage

- [ ] Data disk attached, placed in an LVM volume group, formatted, mounted at `/data`.
- [ ] fstab uses UUID (or LV path) and `nofail`. `findmnt --verify` is clean. Survives a reboot.
- [ ] Disk grown once in the cloud and extended online with `lvextend -r`.

### Application

- [ ] `myapp` (Chapter 09) runs as the `myapp` service account, listens on `127.0.0.1:8080`, writes to `/data/myapp`.
- [ ] systemd unit with `Restart=on-failure`, `MemoryMax=`, and hardening options.
- [ ] nginx reverse proxy on port 80 to `127.0.0.1:8080`:

```nginx
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

- [ ] HTTPS with Let's Encrypt if you have a domain name (Chapter 23).
- [ ] On Rocky/RHEL: SELinux still **enforcing**, with `httpd_can_network_connect` set.

### Security

- [ ] Host firewall allows only 22 (if used), 80, 443.
- [ ] fail2ban protecting SSH (if SSH is exposed).
- [ ] `auditd` rules on `/etc/ssh/sshd_config` and `/etc/sudoers.d/`.
- [ ] Lynis score recorded before and after hardening.
- [ ] No secrets in files, scripts, or history. The VM uses its cloud identity for storage access.

### Operations

- [ ] `health-check.sh` (Chapter 16) runs from a systemd timer every 15 minutes.
- [ ] `disk-alert.sh` runs daily.
- [ ] logrotate rule for `/data/myapp/*.log`. Journal limited to 500 MB.
- [ ] Nightly backup of `/etc` and `/data/myapp` to Azure Blob Storage, S3, or Cloud Storage, keeping 14 days.
- [ ] One file restored from the off-server backup.
- [ ] Monitoring agent installed. Memory and disk space visible in the cloud console. One alert rule (for example disk above 85%).
- [ ] A runbook written for this server: build, patch, restore, decommission (Chapter 23 format).

## Break and fix

Do each exercise, then write three lines: **symptom**, **cause**, **fix**. Use only the tools from this repository.

| # | Break it like this | What you should find |
|---|---|---|
| 1 | Change nginx `proxy_pass` to port `8081` and reload | 502 in the browser, `connect() failed (111: Connection refused)` in the nginx error log |
| 2 | `sudo chmod 700 /data/myapp` and restart `myapp` | Service fails, `Permission denied` in `journalctl -u myapp` |
| 3 | Fill `/data`: `sudo fallocate -l <size> /data/fill.img` until 100% | App errors, `df -h` at 100%, disk alert fires |
| 4 | Delete a log file that `myapp` still has open, while it writes | `df` does not free space, `lsof +L1` shows the file |
| 5 | Enable the host firewall without allowing SSH | Session drops. Recover with Run Command / Session Manager / serial console |
| 6 | Add `UUID=00000000-0000-0000-0000-000000000000 /bad ext4 defaults 0 2` to fstab and reboot | VM in emergency mode. Boot log shows the failed mount. Fix from the serial console |
| 7 | Put `%ops ALL=(ALL) ALL` with a typo into `/etc/sudoers.d/ops` using `tee` (not visudo) | `sudo` stops working. Recover without sudo |
| 8 | Run `stress-ng --vm 1 --vm-bytes 95%` on a VM without swap | OOM kill in `dmesg`, service restarted by systemd |
| 9 | On Rocky: `mv` a new `index.html` from your home directory into the web root | 403, SELinux denial in `ausearch`, fixed with `restorecon` |
| 10 | Point `/etc/resolv.conf` at a DNS server that does not exist (`nameserver 10.255.255.1`) | `apt update` and `curl` fail with name resolution errors |

## Deliverables

If you want this project in a portfolio, publish a repository with:

1. `README.md` describing the architecture, with the diagram above.
2. `cloud-init.yaml` used to build the VM.
3. The systemd units, nginx config, logrotate file, and scripts.
4. The CLI commands used to create and delete the cloud resources.
5. The runbook for the server.
6. The ten break-and-fix write-ups.
7. Evidence: output of the verification commands (remove IP addresses, keys, and account IDs first).

## Clean up

Delete every resource when you finish (Chapters 19 to 21, "Clean up"). Check the billing page the next day to confirm nothing is still running.

## Where to go next

- **Automation:** build the same server with Terraform or Bicep, and configure it with Ansible.
- **Containers:** run `myapp` with Docker or Podman, then on a managed Kubernetes service.
- **Images:** bake a hardened base image with Packer or Azure Image Builder so new servers start secure.
- **Certifications:** Linux Foundation LFCS, Red Hat RHCSA, or the Linux parts of cloud administrator certifications.

[Back to the start](../README.md)
