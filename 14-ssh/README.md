# 14. SSH

SSH is how you reach every Linux server in the cloud. You use it to log in, copy files, run remote commands, and reach private servers through a jump host. Most access problems come from keys, file permissions, or the SSH server configuration. This chapter covers all three.

## What you will learn

- How SSH key authentication works
- Creating and managing keys on Windows, macOS, and Linux
- The client config file that saves typing
- Copying files with `scp` and `rsync`
- Jump hosts and port forwarding
- Hardening the SSH server safely
- Diagnosing "Permission denied (publickey)" and timeouts

## How key authentication works

```text
Your laptop                               Server
-----------                               ------
~/.ssh/id_ed25519      (private key,      ~/.ssh/authorized_keys
                        never leaves)       contains your PUBLIC key
~/.ssh/id_ed25519.pub  (public key)  ---> (copied here once)
```

When you connect, the server checks that you hold the private key that matches a public key in `authorized_keys`. The private key is never sent.

The server also has **host keys** (in `/etc/ssh/ssh_host_*`). The first time you connect, your client stores the server's fingerprint in `~/.ssh/known_hosts`. If it changes later, SSH warns you, because that can mean a different server is answering.

## Create a key

```bash
ssh-keygen -t ed25519 -C "priya@laptop"
```

Output (example):

```text
Generating public/private ed25519 key pair.
Enter file in which to save the key (/home/priya/.ssh/id_ed25519):
Enter passphrase (empty for no passphrase):
Your identification has been saved in /home/priya/.ssh/id_ed25519
Your public key has been saved in /home/priya/.ssh/id_ed25519.pub
```

- `ed25519` is the modern default. Use `-t rsa -b 4096` only for old systems that require RSA.
- Use a **passphrase**. An SSH agent remembers it so you type it once per session.
- The same command works in Windows PowerShell. Keys go to `C:\Users\<you>\.ssh\`.

Show your public key to paste into a cloud portal:

```bash
cat ~/.ssh/id_ed25519.pub
```

## Connect

```bash
ssh azureuser@20.55.100.12
ssh -i ~/.ssh/lab-key.pem ec2-user@3.91.10.20      # specific key file
ssh -p 2222 admin@server                            # non-standard port
ssh azureuser@20.55.100.12 'uptime; df -h /'        # run commands and exit
```

## Add your key to a server

If you can already log in (with a password or another key):

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub azureuser@20.55.100.12
```

`ssh-copy-id` is not available in Windows PowerShell. Use this instead:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh azureuser@20.55.100.12 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

If you cannot log in at all, use the cloud tools to add a key: `az vm user update` (Azure), EC2 Instance Connect or Systems Manager (AWS), or project/instance SSH keys (Google Cloud).

## Key file permissions

SSH refuses keys and `authorized_keys` files that other users can read or write.

| File | Required mode |
|---|---|
| Private key on the client | `600` or `400` |
| `~/.ssh` directory on the server | `700` |
| `~/.ssh/authorized_keys` on the server | `600` |
| Home directory on the server | Not writable by group or others (`755` or stricter) |

On Windows, a `.pem` downloaded from AWS can trigger `UNPROTECTED PRIVATE KEY FILE!`. Fix it in PowerShell:

```powershell
icacls .\lab-key.pem /inheritance:r
icacls .\lab-key.pem /grant:r "$($env:USERNAME):(R)"
```

## The SSH agent

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
ssh-add -l
```

On Windows, enable the built-in agent once (PowerShell as Administrator):

```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519
```

## The client config file

`~/.ssh/config` (on Windows `C:\Users\<you>\.ssh\config`) turns long commands into short names.

```text
Host azure-web
    HostName 20.55.100.12
    User azureuser
    IdentityFile ~/.ssh/id_ed25519

Host aws-web
    HostName 3.91.10.20
    User ec2-user
    IdentityFile ~/.ssh/lab-key.pem

Host bastion
    HostName 52.10.20.30
    User ops

Host app-private
    HostName 10.0.2.15
    User ops
    ProxyJump bastion

Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

Now:

```bash
ssh azure-web
ssh app-private        # goes through bastion automatically
```

`ServerAliveInterval` keeps idle sessions from being dropped by firewalls and load balancers.

## Copying files

```bash
scp app.tar.gz azure-web:/tmp/                    # upload
scp azure-web:/var/log/nginx/error.log .          # download
scp -r ./site azure-web:/tmp/site                 # directory

rsync -avz --progress ./site/ azure-web:/var/www/html/      # sync a directory
rsync -avz --delete ./site/ azure-web:/var/www/html/        # also delete files removed locally
```

`rsync` copies only what changed and can resume. The trailing `/` on the source means "the contents of this directory".

Uploading into a root-owned directory: copy to `/tmp` first, then `sudo mv` on the server, or use `rsync --rsync-path="sudo rsync"`.

## Jump hosts (bastions)

Private servers have no public IP. You reach them through a jump host:

```bash
ssh -J ops@52.10.20.30 ops@10.0.2.15
```

Managed alternatives remove the need for your own bastion VM and for inbound port 22 on the internet:

| Cloud | Service |
|---|---|
| Azure | Azure Bastion, `az network bastion ssh` |
| AWS | Systems Manager Session Manager, EC2 Instance Connect Endpoint |
| Google Cloud | Identity-Aware Proxy (IAP) TCP forwarding, `gcloud compute ssh --tunnel-through-iap` |

## Port forwarding (tunnels)

**Local forward:** reach a service that only listens inside the network.

```bash
ssh -L 5433:10.0.2.20:5432 bastion
```

Now `localhost:5433` on your laptop connects to the database `10.0.2.20:5432` through the bastion. Keep the SSH session open while you use it.

**See a web admin page that listens on localhost only:**

```bash
ssh -L 8080:localhost:8080 azure-web
```

Open `http://localhost:8080` on your laptop.

## SSH server configuration

The server config is `/etc/ssh/sshd_config`, plus files in `/etc/ssh/sshd_config.d/`. Cloud images put their own settings there, and **the first value found wins**, so a setting in `sshd_config.d/50-cloud-init.conf` can override what you set at the bottom of `sshd_config`.

See the settings that are actually in effect:

```bash
sudo sshd -T | grep -Ei 'passwordauthentication|permitrootlogin|pubkeyauthentication|port '
```

Output (example):

```text
port 22
permitrootlogin without-password
pubkeyauthentication yes
passwordauthentication no
```

### Harden it

Create your own file so it is easy to find and is read first (lower number):

```bash
sudo tee /etc/ssh/sshd_config.d/10-hardening.conf > /dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowGroups sudo ssh-users
EOF
```

Change `AllowGroups` to match your system (`wheel` on Red Hat family). Every user who needs SSH must be in one of these groups. Remove the line if you are not sure.

Apply safely:

```bash
sudo sshd -t                           # 1. syntax check: no output means OK
sudo systemctl reload ssh              # 2. Ubuntu (Red Hat family: sshd)
# 3. Open a SECOND terminal and log in again BEFORE closing the first one
```

If the new login fails, fix it from the session that is still open.

> On Ubuntu 24.04, SSH uses **socket activation** (`ssh.socket` listens on the port and starts `ssh.service`). After changing `Port` or `ListenAddress`, run `sudo systemctl daemon-reload` and `sudo systemctl restart ssh.socket`, or the old port stays open. Changing the port also needs the cloud rule and, on Red Hat family, SELinux: `sudo semanage port -a -t ssh_port_t -p tcp 2222`.

## Troubleshooting SSH

### Read the client's side

```bash
ssh -v azureuser@20.55.100.12
```

`-v` shows each step. Look for the last successful line and the first failure.

| Message | Meaning | Check |
|---|---|---|
| `Connection timed out` | Packets never reach SSH. | Cloud rule for port 22 from your IP, public IP, VM running, host firewall. |
| `Connection refused` | Reached the VM, nothing listening. | `sshd` stopped or on another port. Use the serial console or run-command. |
| `Permission denied (publickey)` | Server rejected every key offered. | Wrong user, wrong key, key not in `authorized_keys`, bad permissions. |
| `Host key verification failed` / `REMOTE HOST IDENTIFICATION HAS CHANGED` | Fingerprint differs from `known_hosts`. | If the VM was rebuilt at the same IP this is expected: `ssh-keygen -R <ip>`. Otherwise, investigate. |
| `Too many authentication failures` | Agent offered too many keys. | `ssh -o IdentitiesOnly=yes -i key user@host`. |

### Read the server's side

```bash
sudo journalctl -u ssh -n 30 --no-pager      # Ubuntu
sudo journalctl -u sshd -n 30 --no-pager     # Red Hat family
```

Server messages that point to the fix (examples):

```text
Authentication refused: bad ownership or modes for directory /home/priya
Invalid user admin from 203.0.113.50 port 51234
User priya from 203.0.113.50 not allowed because none of user's groups are listed in AllowGroups
```

### Default usernames

A wrong username gives the same `Permission denied (publickey)` as a wrong key.

| Image | Azure | AWS | Google Cloud |
|---|---|---|---|
| Ubuntu | name you chose (often `azureuser`) | `ubuntu` | your Google username |
| Amazon Linux | n/a | `ec2-user` | n/a |
| RHEL / Rocky | name you chose | `ec2-user` (RHEL), `rocky` (Rocky) | your Google username |
| Debian | name you chose | `admin` | your Google username |

## Lab: Build a key-only, hardened SSH setup

1. Create an ed25519 key with a passphrase on your laptop.
2. Add it to the VM and create a `~/.ssh/config` entry named `lab`.
3. Create group `ssh-users` and add your user.
4. Apply the hardening file above with `AllowGroups ssh-users`.
5. Test: `sudo sshd -t`, reload, log in from a second terminal.
6. Prove password login is off: `ssh -o PubkeyAuthentication=no lab` should fail with `Permission denied (publickey)`.
7. From the server logs, find your successful login and the failed attempt.

## Next

[15. Security Hardening](../15-security-hardening/README.md)
