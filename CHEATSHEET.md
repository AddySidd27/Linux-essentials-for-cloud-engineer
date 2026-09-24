# Linux Cheat Sheet for Cloud Engineers

One page of the commands used most often in this guide. Ubuntu first; Red Hat family differences in brackets. Chapter numbers point to the full explanation.

## Identify the server (01)

```bash
cat /etc/os-release          # distribution and version
uname -r; uname -m           # kernel; architecture
hostnamectl; uptime          # name, virtualisation, uptime, load
nproc; free -h; df -hT       # CPUs, memory, disks
ip -brief address            # IP addresses
id; sudo -l                  # who am I, what can I sudo
```

## Files and text (03, 04)

```bash
ls -lah; cd -; pwd
cp -a src dst                # copy keeping permissions
cp file{,.bak}               # quick backup
find / -xdev -type f -size +500M 2>/dev/null
grep -rn "text" /etc/        # search recursively with line numbers
grep -Ev '^\s*(#|$)' file    # config without comments/blank lines
tail -f /var/log/syslog      # follow a log ([/var/log/messages])
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head
tar -czf backup.tgz dir; tar -xzf backup.tgz -C /tmp
echo "text" | sudo tee -a /root-owned/file
```

## Users and permissions (06, 07)

```bash
sudo useradd -m -s /bin/bash user; sudo passwd user
sudo usermod -aG sudo user   # [wheel]; always -aG
sudo visudo -f /etc/sudoers.d/name
sudo usermod -L -s /usr/sbin/nologin user     # lock
chmod 640 file; chmod u+x script.sh; chown user:group file
namei -l /full/path          # permissions along a path
sudo -u www-data cat /path   # test access as another user
```

## Packages (08)

```bash
sudo apt update && sudo apt upgrade -y        # [sudo dnf upgrade -y]
sudo apt install -y pkg                       # [sudo dnf install -y pkg]
apt list --upgradable                         # [dnf check-update]
dpkg -S /path/file                            # [rpm -qf /path/file]
[ -f /var/run/reboot-required ] && echo reboot   # [needs-restarting -r]
```

## Services, jobs, logs (09, 10, 11)

```bash
systemctl status nginx --no-pager
sudo systemctl enable --now nginx
sudo systemctl restart nginx
sudo systemctl reload nginx                   # re-read config, keep connections
systemctl --failed
sudo systemctl daemon-reload                  # after editing unit files
sudo systemctl edit nginx                     # override without touching the original
journalctl -u nginx -n 50 --no-pager
journalctl -p err -b                          # errors this boot
journalctl -b -1 -n 50                        # end of previous boot
sudo dmesg -T | tail
crontab -e; systemctl list-timers
```

## Storage (12)

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
sudo blkid                                    # UUIDs
sudo parted /dev/sdX --script mklabel gpt mkpart data 0% 100%
sudo mkfs.ext4 /dev/sdX1                      # [mkfs.xfs]
# fstab: UUID=...  /data  ext4  defaults,nofail  0  2
sudo findmnt --verify && sudo mount -a        # ALWAYS before reboot
sudo growpart /dev/sdX 1 && sudo resize2fs /dev/sdX1    # [xfs_growfs /mount]
sudo lvextend -r -L +10G /dev/vg/lv
ls -l /dev/disk/azure/scsi1/                  # Azure LUNs
lsblk -o NAME,SERIAL                          # AWS: serial = EBS volume ID
```

## Network (13)

```bash
ip route; ip route get 8.8.8.8
resolvectl status; getent hosts name
sudo ss -tulpn                                # listening ports and processes
curl -sI http://localhost/
nc -zv host 443
sudo tcpdump -ni any port 80 -c 10
sudo ufw status verbose                       # [sudo firewall-cmd --list-all]
```

## SSH (14)

```bash
ssh-keygen -t ed25519
ssh -i key user@host; ssh -v user@host        # verbose for troubleshooting
ssh -J bastion user@private-ip                # jump host
ssh -L 8080:localhost:8080 host               # tunnel
rsync -avz ./dir/ host:/path/
sudo sshd -t && sudo systemctl reload ssh     # [sshd]; test from a 2nd session
ssh-keygen -R host                            # remove old host key
```

## Performance (17)

```bash
uptime; vmstat 1 5; mpstat -P ALL 1 3
free -h                                       # read "available"
iostat -xz 1 3; sudo pidstat -d 1 5
ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu | head
sudo dmesg -T | grep -i oom
```

## Security (15)

```bash
sudo fail2ban-client status sshd
getenforce; ls -Z file; sudo restorecon -Rv /path       # SELinux
sudo ausearch -m avc -ts recent                         # SELinux denials
sudo aa-status                                          # AppArmor
timedatectl; chronyc tracking
```

## cloud-init and metadata (18)

```bash
cloud-init status --long
sudo tail -n 40 /var/log/cloud-init-output.log
# Azure
curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01"
# AWS (IMDSv2)
T=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
curl -s -H "X-aws-ec2-metadata-token: $T" http://169.254.169.254/latest/meta-data/instance-id
# Google Cloud
curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name
```

## Cloud recovery when SSH fails (19, 20, 21)

| | Azure | AWS | Google Cloud |
|---|---|---|---|
| Boot log | `az vm boot-diagnostics get-boot-log` | `aws ec2 get-console-output --latest` | `gcloud compute instances get-serial-port-output` |
| Run a command | `az vm run-command invoke --command-id RunShellScript` | `aws ssm send-command --document-name AWS-RunShellScript` | serial console or `gcloud compute ssh` |
| Shell without port 22 | Azure Bastion | `aws ssm start-session` | `gcloud compute ssh --tunnel-through-iap` |
| Console | Serial Console | EC2 Serial Console | `gcloud compute connect-to-serial-port` |
| Reset key | `az vm user update --ssh-key-value` | EC2 Instance Connect | `gcloud compute ssh` / OS Login |
| Fix disk offline | `az vm repair create` | Rescue instance | Rescue VM |

## Evidence snapshot before escalating (22)

```bash
{ date -Is; hostnamectl; uptime; free -h; df -hT; systemctl --failed --no-pager;
  journalctl -p err -b --no-pager | tail -50; sudo dmesg -T | tail -50; } > ~/evidence.txt 2>&1
```
