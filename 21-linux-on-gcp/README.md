# 21. Linux on Google Cloud

Google Cloud uses the same Linux skills as Azure and AWS. The main differences are how SSH keys are managed (OS Login or metadata keys), how firewall rules target instances (network tags), and how disks are named inside the VM. This chapter covers the full lifecycle with the `gcloud` CLI.

## What you will learn

- Creating a VM and a firewall rule limited to your IP
- Connecting with `gcloud compute ssh`, OS Login, and IAP
- Adding and resizing persistent disks
- Changing machine type
- Recovery: serial port output and the interactive serial console
- Service accounts, snapshots, and cleanup

## Before you start

- A Google Cloud project with billing enabled, and the Google Cloud CLI (`gcloud version`), or use **Cloud Shell** in the console.

```bash
gcloud auth login
gcloud config set project my-project-id
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a
gcloud services enable compute.googleapis.com
MYIP=$(curl -s https://ifconfig.me)
```

## Step 1: Firewall rule

Google Cloud firewall rules belong to the VPC network and apply to instances through **network tags**. The `default` network has a rule that allows SSH from everywhere (`default-allow-ssh`). Replace it with a narrow rule for your lab:

```bash
gcloud compute firewall-rules create lab-allow-ssh-my-ip \
  --network default --direction INGRESS --action ALLOW \
  --rules tcp:22 --source-ranges "$MYIP/32" --target-tags lab-web

gcloud compute firewall-rules create lab-allow-http \
  --network default --direction INGRESS --action ALLOW \
  --rules tcp:80 --source-ranges 0.0.0.0/0 --target-tags lab-web
```

If your organisation allows it, delete or restrict `default-allow-ssh` in lab projects:

```bash
gcloud compute firewall-rules list
gcloud compute firewall-rules update default-allow-ssh --source-ranges "$MYIP/32"
```

## Step 2: Create the VM

```bash
gcloud compute instances create web01 \
  --machine-type e2-small \
  --image-family ubuntu-2404-lts-amd64 --image-project ubuntu-os-cloud \
  --boot-disk-size 20GB --boot-disk-type pd-balanced \
  --tags lab-web \
  --shielded-secure-boot \
  --metadata-from-file user-data=cloud-init.yaml
```

Output (example):

```text
NAME   ZONE           MACHINE_TYPE  INTERNAL_IP  EXTERNAL_IP    STATUS
web01  us-central1-a  e2-small      10.128.0.5   34.123.45.67   RUNNING
```

- `--tags lab-web` connects the instance to the firewall rules above.
- Remove `--metadata-from-file` if you have no cloud-config yet (Chapter 18).
- Other images: `--image-family rocky-linux-9 --image-project rocky-linux-cloud`, `--image-family debian-12 --image-project debian-cloud`. List them with `gcloud compute images list`.

## Step 3: Connect

**Option A: gcloud manages the key**

```bash
gcloud compute ssh web01
```

The first time, `gcloud` creates a key in `~/.ssh/google_compute_engine` and adds the public key to the project or instance metadata, or to your OS Login profile. Your Linux username is derived from your Google account.

**Option B: your own key with a normal SSH client**

```bash
gcloud compute instances add-metadata web01 \
  --metadata ssh-keys="ops:$(cat ~/.ssh/id_ed25519.pub)"
ssh -i ~/.ssh/id_ed25519 ops@34.123.45.67
```

Metadata `ssh-keys` replaces the instance's existing list, so include every key you need. Google's guest agent creates the `ops` user automatically.

**Option C: OS Login (recommended for teams)**

OS Login ties Linux accounts to IAM. Access is granted and revoked with IAM roles (`roles/compute.osLogin` or `roles/compute.osAdminLogin` for sudo) instead of copying keys:

```bash
gcloud compute instances add-metadata web01 --metadata enable-oslogin=TRUE
gcloud compute ssh web01
```

**Option D: no public IP, through IAP**

```bash
gcloud compute firewall-rules create lab-allow-iap-ssh --network default \
  --direction INGRESS --action ALLOW --rules tcp:22 \
  --source-ranges 35.235.240.0/20 --target-tags lab-web
gcloud compute ssh web01 --tunnel-through-iap
```

`35.235.240.0/20` is the range IAP uses to reach your VMs.

Google-specific checks on the VM:

```bash
systemctl status google-guest-agent --no-pager
curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name
```

## Step 4: Add a persistent disk

```bash
gcloud compute disks create web01-data --size 20GB --type pd-balanced
gcloud compute instances attach-disk web01 --disk web01-data --device-name web01-data
```

On the VM, Google Cloud creates a stable link that uses the device name:

```bash
ls -l /dev/disk/by-id/google-*
```

Output (example):

```text
lrwxrwxrwx 1 root root  9 Sep 23 14:02 /dev/disk/by-id/google-persistent-disk-0 -> ../../sda
lrwxrwxrwx 1 root root  9 Sep 23 14:10 /dev/disk/by-id/google-web01-data -> ../../sdb
```

`/dev/sdb` is the new disk. Partition, format, mount, and add to fstab as in [Chapter 12](../12-storage-and-filesystems/README.md#add-a-data-disk-step-by-step). Machine types that use NVMe (for example C3, N4) show `nvme0n2` instead.

## Step 5: Resize a disk

Disks can grow while attached:

```bash
gcloud compute disks resize web01-data --size 40GB
```

Then on the VM: `growpart` and `resize2fs` or `xfs_growfs` (Chapter 12). The boot disk grows the same way. Ubuntu images grow the root partition automatically at the next boot.

## Step 6: Change machine type

```bash
gcloud compute instances stop web01
gcloud compute instances set-machine-type web01 --machine-type e2-medium
gcloud compute instances start web01
```

A stopped VM is not billed for vCPU and memory. Disks and static IPs are still billed. The ephemeral external IP can change after stop and start; reserve a static address with `gcloud compute addresses create` if you need a fixed one.

## Step 7: Service account

Every VM runs as a service account. The default Compute Engine service account often has broad permissions in older projects. Use a dedicated one with only the roles the application needs:

```bash
gcloud iam service-accounts create web01-sa --display-name "web01"
gcloud compute instances stop web01
gcloud compute instances set-service-account web01 \
  --service-account "web01-sa@$(gcloud config get-value project).iam.gserviceaccount.com" \
  --scopes cloud-platform
gcloud compute instances start web01
```

On the VM, `gcloud` and Google client libraries use this identity automatically through the metadata server (Chapter 18).

## Step 8: Snapshots

```bash
gcloud compute snapshots create web01-data-$(date +%F) --source-disk web01-data --source-disk-zone us-central1-a
gcloud compute snapshots list
```

Schedule snapshots with a snapshot schedule resource policy (`gcloud compute resource-policies create snapshot-schedule`) and attach it to the disk.

## Recovery tools

### Serial port output

```bash
gcloud compute instances get-serial-port-output web01 | tail -40
```

Shows boot messages, including fstab mount failures.

### Interactive serial console

```bash
gcloud compute instances add-metadata web01 --metadata serial-port-enable=TRUE
gcloud compute connect-to-serial-port web01
```

You need a Linux user with a **password** to log in at the console prompt. Disable `serial-port-enable` again when you are done, because it is an extra access path.

### Reset SSH keys

If keys are lost, `gcloud compute ssh` adds a new key through metadata or OS Login, as long as the guest agent is running. If the guest agent is broken, use the serial console, or attach the boot disk to a rescue VM (same steps as the AWS rescue instance in Chapter 20).

## Monitoring

- **Cloud Monitoring** shows CPU, disk, and network without an agent.
- The **Ops Agent** adds memory, disk space, and log collection to Cloud Logging.
- Patching at scale: **VM Manager OS patch management**.

## Step 9: Clean up

```bash
gcloud compute instances delete web01 --quiet
gcloud compute disks delete web01-data --quiet
gcloud compute firewall-rules delete lab-allow-ssh-my-ip lab-allow-http lab-allow-iap-ssh --quiet
gcloud compute snapshots list --format="value(name)" | grep '^web01-' | xargs -r gcloud compute snapshots delete --quiet
gcloud iam service-accounts delete "web01-sa@$(gcloud config get-value project).iam.gserviceaccount.com" --quiet
```

Deleting the instance deletes its boot disk by default. Attached data disks are kept unless they were created with auto-delete.

## Lab: Full Google Cloud lifecycle

1. Create `web01` with network tag `lab-web`, a cloud-config, and SSH allowed from your IP only.
2. Connect with `gcloud compute ssh`, then switch the instance to OS Login.
3. Add a 20 GB data disk, find it under `/dev/disk/by-id/`, mount it at `/data` with fstab, reboot, confirm.
4. Resize the disk to 40 GB and grow the filesystem online.
5. Remove the external IP path by connecting through IAP.
6. Break fstab on purpose, read the serial port output, and fix it through the serial console.
7. Clean up everything.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| SSH times out | No firewall rule for the instance's tag, or wrong source IP. | `gcloud compute instances describe web01 --format="value(tags.items)"` and compare with firewall rules. |
| `Permission denied (publickey)` with OS Login | Missing IAM role. | Grant `roles/compute.osLogin` (or `osAdminLogin`). |
| Keys added to metadata but login fails | OS Login is enabled, so metadata keys are ignored. | Use OS Login, or disable it for that instance. |
| Disk not found at `/dev/sdb` | NVMe machine type or different order. | Use `/dev/disk/by-id/google-<device-name>`. |
| VM uses the default service account with Editor role | Old project default. | Dedicated service account with minimal roles. |

## Next

[22. Troubleshooting](../22-troubleshooting/README.md)
