# 23. Operations Runbooks

A runbook is a written procedure for a routine task. It makes the work repeatable, lets someone else do it at 03:00, and gives you a record of what was done. Each runbook below has the same parts: **when to use it**, **before you start**, **steps**, **verify**, and **roll back**.

Copy these into your team's wiki and adjust them to your environment.

## Contents

- [Build a new server](#build-a-new-server)
- [Patch a server](#patch-a-server)
- [Onboard and offboard a user](#onboard-and-offboard-a-user)
- [Extend a disk that is filling up](#extend-a-disk-that-is-filling-up)
- [Add HTTPS with Let's Encrypt](#add-https-with-lets-encrypt)
- [Back up and restore files](#back-up-and-restore-files)
- [Planned restart or maintenance](#planned-restart-or-maintenance)
- [Decommission a server](#decommission-a-server)
- [Routine checks](#routine-checks)
- [Change record template](#change-record-template)

---

## Build a new server

**When:** a new Linux VM is requested.

**Before you start:** owner, purpose, environment, size, OS, network, open ports, data disks, backup requirement, and who needs access.

**Steps:**

1. Create the VM with SSH from approved ranges only, IMDSv2 on AWS, and a cloud-config (Chapters 18 to 21).
2. Tag it: `owner`, `environment`, `application`, `cost-center`.
3. Patch it fully and reboot (runbook below).
4. Set the hostname and timezone (UTC).
5. Create named admin accounts and the service account. Harden SSH (Chapter 14).
6. Enable the host firewall with only the required ports (Chapter 13).
7. Attach and mount data disks by UUID with `nofail` (Chapter 12).
8. Install the cloud monitoring agent and confirm metrics and logs arrive.
9. Enable backups (cloud backup service or snapshots).
10. Record the server in the inventory.

**Verify:**

```bash
hostnamectl; timedatectl | grep -E 'Time zone|synchronized'
sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin'
sudo ss -tulpn
findmnt --verify && df -hT
systemctl --failed --no-pager
```

---

## Patch a server

**When:** monthly patch window, or urgently for a critical security advisory.

**Before you start:**

- Change approved and users informed if a reboot is needed.
- Snapshot of the OS disk, or confirmed recent backup.
- Console access tested (Run Command, Session Manager, or serial console) in case the server does not come back.
- For clusters or load-balanced servers: patch one node at a time.

**Steps (Ubuntu):**

```bash
tmux new -s patch                                  # survives a dropped SSH session
uname -r | tee ~/patch-$(date +%F).log
apt list --upgradable 2>/dev/null | tee -a ~/patch-$(date +%F).log
sudo apt update && sudo apt upgrade -y
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required.pkgs
sudo reboot
```

**Steps (Red Hat family):**

```bash
tmux new -s patch
sudo dnf check-update | tee ~/patch-$(date +%F).log
sudo dnf upgrade -y
sudo needs-restarting -r || sudo reboot
```

**Verify:**

```bash
uname -r
systemctl --failed --no-pager
systemctl is-active nginx myapp          # your application services
curl -sI http://localhost/ | head -1
journalctl -p err -b --no-pager | tail
```

**Roll back:**

- Single package: `sudo apt install <pkg>=<old-version>` or `sudo dnf history undo <id>`.
- Kernel: boot the previous kernel from GRUB (Chapter 22).
- Whole server: restore the snapshot.

At scale, use **Azure Update Manager**, **AWS Systems Manager Patch Manager**, or **GCP VM Manager** with maintenance windows instead of patching by hand.

---

## Onboard and offboard a user

**Onboard:**

```bash
sudo useradd -m -s /bin/bash -c "Full Name" jdoe
sudo usermod -aG ssh-users jdoe                     # group allowed by AllowGroups, if used
sudo install -d -m 700 -o jdoe -g jdoe /home/jdoe/.ssh
echo "<public key from the user>" | sudo tee /home/jdoe/.ssh/authorized_keys > /dev/null
sudo chown jdoe:jdoe /home/jdoe/.ssh/authorized_keys && sudo chmod 600 /home/jdoe/.ssh/authorized_keys
# sudo only if approved:
sudo usermod -aG sudo jdoe                          # wheel on Red Hat family
```

**Verify:** the user logs in, and `sudo -l -U jdoe` shows only the approved rights.

**Offboard:**

```bash
sudo usermod -L -s /usr/sbin/nologin jdoe
sudo mv /home/jdoe/.ssh/authorized_keys /home/jdoe/.ssh/authorized_keys.disabled
sudo pkill -u jdoe
sudo crontab -l -u jdoe                              # review, then: sudo crontab -r -u jdoe
sudo find / -xdev -user jdoe -not -path '/home/jdoe/*' 2>/dev/null   # files elsewhere
```

After the retention period: `sudo userdel -r jdoe`.

For fleets, prefer central identity: Microsoft Entra ID login for Azure Linux VMs, AWS Systems Manager with IAM, or GCP OS Login. Then offboarding is one change in one place.

---

## Extend a disk that is filling up

**When:** disk usage alert above 80%.

1. Find what is using space (Chapter 22, "Disk full"). Clean up if it is logs, caches, or old files.
2. If the growth is real, increase the disk in the cloud:
   - Azure: `az disk update -g RG -n DISK --size-gb NEW` (OS disk: deallocate first)
   - AWS: `aws ec2 modify-volume --volume-id VOL --size NEW`
   - GCP: `gcloud compute disks resize DISK --size NEWGB`
3. On the server:

```bash
lsblk
sudo growpart /dev/sdc 1                 # disk and partition number
sudo resize2fs /dev/sdc1                 # ext4
# sudo xfs_growfs /data                  # xfs
# LVM: sudo pvresize /dev/sdc1 && sudo lvextend -r -l +100%FREE /dev/datavg/datalv
```

**Verify:** `df -h` shows the new size. Update the alert baseline if needed.

**Roll back:** not possible, disks do not shrink. That is why step 1 comes first.

---

## Add HTTPS with Let's Encrypt

**When:** a public nginx site needs a trusted certificate.

**Before you start:** a DNS name (`www.example.com`) pointing to the server's public IP, and ports 80 and 443 open in the cloud rules and host firewall.

```bash
sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak   # your site file
sudo apt install -y certbot python3-certbot-nginx      # Red Hat family: EPEL, then certbot python3-certbot-nginx
sudo certbot --nginx -d www.example.com --redirect -m ops@example.com --agree-tos -n
```

Certbot edits the nginx server block, installs the certificate, and adds a redirect from HTTP to HTTPS.

**Verify:**

```bash
curl -sI https://www.example.com | head -1
sudo certbot certificates
systemctl list-timers | grep certbot
sudo certbot renew --dry-run
```

Certificates are valid for 90 days and renew automatically through the timer. The dry run proves renewal will work.

**Roll back:** restore the backup and reload:

```bash
sudo cp /etc/nginx/sites-available/default.bak /etc/nginx/sites-available/default
sudo nginx -t && sudo systemctl reload nginx
```

---

## Back up and restore files

**When:** before changes, and on a schedule for data that is not covered by snapshots.

**Backup** with the script from Chapter 16:

```bash
sudo /usr/local/bin/backup-dir.sh /etc /var/backups/etc 14
```

Copy backups off the server. A backup on the same disk does not survive losing the disk:

```bash
# Azure Blob Storage with the VM's managed identity
az login --identity
az storage blob upload-batch --account-name mystorageacct -d backups/$(hostname) -s /var/backups --auth-mode login

# Amazon S3 with the instance role
aws s3 sync /var/backups s3://my-backup-bucket/$(hostname)/
```

**Restore a single file:**

```bash
mkdir -p /tmp/restore
tar -xzf /var/backups/etc/etc-2026-09-20_020001.tar.gz -C /tmp/restore etc/nginx/nginx.conf
diff /tmp/restore/etc/nginx/nginx.conf /etc/nginx/nginx.conf
sudo cp /tmp/restore/etc/nginx/nginx.conf /etc/nginx/nginx.conf
```

**Verify:** a backup you have never restored is not a backup. Restore a sample file every month and record it.

---

## Planned restart or maintenance

1. Announce the window.
2. If behind a load balancer, drain the server first (remove from the backend pool or target group).
3. Record the state:

```bash
systemctl list-units --type=service --state=running --no-pager > ~/running-before.txt
```

4. Restart the service (`sudo systemctl restart myapp`) or the server (`sudo reboot`).
5. Compare:

```bash
systemctl list-units --type=service --state=running --no-pager > ~/running-after.txt
diff ~/running-before.txt ~/running-after.txt
systemctl --failed --no-pager
```

6. Test the application, add the server back to the load balancer, close the change.

---

## Decommission a server

1. Confirm with the owner that it is no longer needed, and the date.
2. Stop the application and remove the server from load balancers, DNS, and monitoring.
3. Take a final backup or snapshot and record where it is and how long it is kept.
4. Stop (deallocate) the VM and wait an agreed period (for example, one week) in case something breaks.
5. Delete the VM, disks, public IP, NIC, security rules, and DNS records. On Azure, check the resource group. On AWS, check volumes, Elastic IPs, snapshots, and IAM roles.
6. Remove it from the inventory and close the request.

---

## Routine checks

**Daily** (automate with the health check script and alerts):

```bash
systemctl --failed --no-pager
df -hT | awk 'NR==1 || $6+0 >= 80'
journalctl -p err --since yesterday --no-pager | tail -20
```

**Weekly:**

- Pending security updates: `apt list --upgradable 2>/dev/null | grep -c security` or `dnf updateinfo list --security`
- Failed logins: `sudo journalctl -u ssh --since "7 days ago" | grep -c "Failed"` (`sshd` on Red Hat family)
- Backups completed and one test restore

**Monthly:**

- Patch window
- Review users and sudo rights: `getent group sudo`, `ls /etc/sudoers.d/`
- Review open ports and cloud rules
- Check certificate expiry: `sudo certbot certificates`

---

## Change record template

```text
Change ID:
Server(s):
Requested by:              Approved by:
Window (UTC):
Reason:
Risk and impact:
Pre-checks done:           Snapshot/backup:
Steps:
Verification:
Rollback plan:
Result:                    Completed by / time:
Notes and follow-ups:
```

## Next

[24. Capstone Project](../24-capstone-project/README.md)
