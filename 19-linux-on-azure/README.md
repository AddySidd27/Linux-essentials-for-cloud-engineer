# 19. Linux on Azure

This chapter takes a Linux VM on Azure through its whole life: create it securely, connect, add and grow disks, resize, recover when you are locked out or it will not boot, and delete it. Every step is shown with the Azure CLI, and the portal location is given where it helps.

## What you will learn

- Creating a Linux VM with SSH restricted to your IP
- Connecting with SSH and with Azure Bastion
- Attaching, mounting, and expanding managed disks
- Resizing the VM and understanding stop vs deallocate
- Recovery tools: boot diagnostics, Serial Console, Run Command, VMAccess
- The Azure Linux agent, managed identity, and snapshots
- Cleaning up so nothing keeps costing money

## Before you start

- An Azure subscription and the Azure CLI (`az version`). You can also use **Azure Cloud Shell** in the portal, which has everything installed.
- An SSH key pair (Chapter 14).
- Commands below use Bash line continuation (`\`). In PowerShell, replace `\` at the end of lines with a backtick (`` ` ``).

```bash
az login
az account show --query "{name:name, id:id}" -o table
```

Set names once so every command below works as written:

```bash
RG=lab-rg
LOC=eastus
VM=web01
MYIP=$(curl -s https://ifconfig.me)
echo "$MYIP"
```

## Step 1: Create the VM

```bash
az group create -n "$RG" -l "$LOC" -o table

az vm create \
  -g "$RG" -n "$VM" \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_B2s \
  --admin-username azureuser \
  --ssh-key-values ~/.ssh/id_ed25519.pub \
  --public-ip-sku Standard \
  --nsg-rule NONE \
  -o table
```

Output (example):

```text
ResourceGroup    PowerState    PublicIpAddress    PrivateIpAddress    Location
---------------  ------------  -----------------  ------------------  ----------
lab-rg           VM running    20.55.100.12       10.0.0.4            eastus
```

What this created: a virtual network and subnet, a network security group (NSG) named `web01NSG`, a public IP, a network interface, an OS disk, and the VM.

- `--image` uses the full image name (publisher:offer:sku:version). Find others with `az vm image list --publisher Canonical --all -o table` or `az vm image list -o table` for popular images.
- `--nsg-rule NONE` stops Azure from opening SSH to the whole internet. You add a narrow rule next.
- Add `--custom-data cloud-init.yaml` to configure the VM at first boot (Chapter 18).

**Portal:** Virtual machines > Create > Azure virtual machine. On the Networking tab, set **Public inbound ports** to None and add the rule below afterwards.

## Step 2: Allow SSH from your IP only

```bash
az network nsg rule create \
  -g "$RG" --nsg-name "${VM}NSG" \
  -n allow-ssh-from-my-ip --priority 1000 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "$MYIP/32" \
  --destination-port-ranges 22 \
  -o table
```

Allow HTTP from anywhere if this is a public web server:

```bash
az network nsg rule create -g "$RG" --nsg-name "${VM}NSG" \
  -n allow-http --priority 1010 --access Allow --protocol Tcp \
  --destination-port-ranges 80 --source-address-prefixes Internet -o table
```

Check the effective rules on the network card (includes rules from any subnet NSG):

```bash
NIC_ID=$(az vm show -g "$RG" -n "$VM" --query "networkProfile.networkInterfaces[0].id" -o tsv)
az network nic list-effective-nsg --ids "$NIC_ID" -o table
```

## Step 3: Connect

```bash
IP=$(az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)
ssh azureuser@"$IP"
```

Once connected, run the checks from Chapter 01. Things specific to Azure:

```bash
systemctl status walinuxagent --no-pager      # Azure Linux agent (service is waagent on Red Hat family)
lsblk                                         # sdb mounted on /mnt is the TEMPORARY disk
cloud-init status --long
```

### Connect without a public IP: Azure Bastion

For production, remove public IPs and SSH through Azure Bastion. With the Standard or Premium SKU and the native client enabled:

```bash
az extension add -n bastion
az network bastion ssh -g "$RG" -n my-bastion \
  --target-resource-id "$(az vm show -g "$RG" -n "$VM" --query id -o tsv)" \
  --auth-type ssh-key --username azureuser --ssh-key ~/.ssh/id_ed25519
```

Bastion needs a subnet named `AzureBastionSubnet` in the same virtual network. It is billed per hour, so remove it from lab environments when you are done.

## Step 4: Add a data disk

```bash
az vm disk attach -g "$RG" --vm-name "$VM" \
  --name "${VM}-data" --new --size-gb 32 --sku StandardSSD_LRS -o table
```

On the VM:

```bash
lsblk -o NAME,HCTL,SIZE,MOUNTPOINTS
ls -l /dev/disk/azure/scsi1/
```

Output (example):

```text
lrwxrwxrwx 1 root root 12 Sep 23 13:05 lun0 -> ../../../sdc
```

LUN 0 is `/dev/sdc`. Now partition, format, mount, and add to fstab exactly as in [Chapter 12](../12-storage-and-filesystems/README.md#add-a-data-disk-step-by-step).

> **Never use `/dev/sdb` or `/mnt` for data.** That is the temporary disk. It is erased when the VM is deallocated, resized, or moved to another host.

## Step 5: Expand disks

**Data disk.** Many disk types support expanding while the VM runs. If Azure rejects the change, deallocate the VM first.

```bash
az disk update -g "$RG" -n "${VM}-data" --size-gb 64 -o table
```

**OS disk.** Deallocate, expand, start:

```bash
OSDISK=$(az vm show -g "$RG" -n "$VM" --query "storageProfile.osDisk.name" -o tsv)
az vm deallocate -g "$RG" -n "$VM"
az disk update -g "$RG" -n "$OSDISK" --size-gb 64 -o table
az vm start -g "$RG" -n "$VM"
```

Then inside the VM, grow the partition and filesystem (Chapter 12, "Grow a disk"). On Ubuntu cloud images, the root partition usually grows automatically at boot. Confirm with `df -h /`.

Disks can grow but **cannot shrink**.

## Step 6: Resize, stop, and deallocate

```bash
az vm list-vm-resize-options -g "$RG" -n "$VM" -o table | head
az vm resize -g "$RG" -n "$VM" --size Standard_B2ms
```

Resizing restarts the VM. If the new size is not available on the current hardware, deallocate first.

| Action | Command | Compute billed? | Keeps public IP? | Temp disk |
|---|---|---|---|---|
| Stop from inside Linux (`sudo poweroff`) | n/a | **Yes**, VM still allocated | Yes | Kept |
| Stop (allocated) | `az vm stop` | **Yes** | Yes | Kept |
| Deallocate | `az vm deallocate` | No | Standard static IP: yes | **Erased** |

To stop paying for compute, **deallocate**. Disks and static public IPs are still billed.

## Step 7: Give the VM an identity

```bash
az vm identity assign -g "$RG" -n "$VM"
PRINCIPAL=$(az vm show -g "$RG" -n "$VM" --query identity.principalId -o tsv)
az role assignment create --assignee "$PRINCIPAL" --role Reader --scope "$(az group show -n "$RG" --query id -o tsv)"
```

On the VM (install the Azure CLI first, Chapter 08):

```bash
az login --identity
az resource list -g lab-rg -o table
```

No password or key was stored on the VM (Chapter 18).

## Step 8: Snapshots

Take a snapshot before risky changes:

```bash
az snapshot create -g "$RG" -n "${VM}-os-$(date +%F)" \
  --source "$(az vm show -g "$RG" -n "$VM" --query storageProfile.osDisk.managedDisk.id -o tsv)" \
  --incremental true -o table
```

Restore by creating a disk from the snapshot (`az disk create --source <snapshot>`) and swapping the OS disk (`az vm update --os-disk <disk-id>` while deallocated). For scheduled backups, use **Azure Backup**.

## Recovery tools

When you cannot SSH in, you still have options. Try them in this order.

### 1. Boot diagnostics: see the console output

```bash
az vm boot-diagnostics enable -g "$RG" -n "$VM"
az vm boot-diagnostics get-boot-log -g "$RG" -n "$VM" | tail -40
```

The log shows kernel messages, cloud-init output, and errors such as fstab mount failures. **Portal:** VM > Help > Boot diagnostics > Serial log.

### 2. Run Command: run a script through the Azure agent

Works without network access to the VM, as long as the Azure Linux agent is running.

```bash
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript \
  --scripts "systemctl status ssh --no-pager; ss -ltnp; tail -n 20 /var/log/auth.log"
```

Output (example, trimmed):

```json
{
  "value": [
    {
      "message": "Enable succeeded: \n[stdout]\n● ssh.service - OpenBSD Secure Shell server\n     Active: active (running)...\n[stderr]\n"
    }
  ]
}
```

Fix common problems without logging in:

```bash
# Disable a host firewall that blocks SSH
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "ufw disable"

# Fix permissions on authorized_keys
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript \
  --scripts "chmod 700 /home/azureuser/.ssh; chmod 600 /home/azureuser/.ssh/authorized_keys; chown -R azureuser:azureuser /home/azureuser/.ssh"
```

### 3. VMAccess: reset keys, users, or SSH config

```bash
az vm user update -g "$RG" -n "$VM" --username azureuser --ssh-key-value ~/.ssh/id_ed25519.pub
az vm user reset-ssh -g "$RG" -n "$VM"         # restores a default sshd_config
az vm user update -g "$RG" -n "$VM" --username rescueadmin --password '<a-strong-password>'
```

`reset-ssh` replaces `sshd_config` with a default copy. Re-apply your hardening afterwards.

### 4. Serial Console: an interactive console

Use this when the VM is not booting correctly or the agent is not running (for example, stuck in emergency mode after a bad fstab line).

Requirements: boot diagnostics enabled, and a local user with a **password** (keys cannot be used at a console login prompt). Create one with VMAccess (above) if needed.

```bash
az extension add -n serial-console
az serial-console connect -g "$RG" -n "$VM"
```

**Portal:** VM > Help > Serial console. Fixing an fstab problem from emergency mode is covered in [22. Troubleshooting](../22-troubleshooting/README.md#server-does-not-boot-after-an-fstab-change).

### 5. Repair VM: attach the broken disk to a rescue VM

If nothing else works, the `vm-repair` extension creates a rescue VM, attaches a copy of the broken OS disk, and swaps it back after you fix it:

```bash
az extension add -n vm-repair
az vm repair create -g "$RG" -n "$VM" --repair-username rescue --repair-password '<a-strong-password>' --associate-public-ip --verbose
# SSH to the rescue VM (it is created in a new resource group), mount the attached disk, fix files
az vm repair restore -g "$RG" -n "$VM" --verbose
```

## The Azure Linux agent

The agent (`walinuxagent` on Ubuntu, `waagent` on Red Hat family) handles extensions, Run Command, and VMAccess. If it is broken, those tools stop working.

```bash
systemctl status walinuxagent --no-pager
sudo tail -n 30 /var/log/waagent.log
```

The agent must reach `168.63.129.16`. Custom DNS, host firewalls, or proxy settings that block it make the VM show **Not Ready** in the portal.

## Monitoring

- **Metrics** (CPU, disk, network) appear in the portal without an agent.
- **Guest metrics and logs** (memory, disk space, syslog) need the **Azure Monitor Agent** and a **Data Collection Rule** sending to a Log Analytics workspace. Enable it from VM > Monitoring > Insights, or with `az vm extension set --name AzureMonitorLinuxAgent --publisher Microsoft.Azure.Monitor`.
- Patching at scale: **Azure Update Manager**.

## Step 9: Clean up

```bash
az group delete -n "$RG" --yes --no-wait
```

Deleting the resource group deletes the VM, disks, network, public IP, and snapshots inside it. Confirm nothing is left:

```bash
az group exists -n "$RG"
```

## Lab: Full Azure lifecycle

1. Create `web01` with the cloud-config from Chapter 18 and SSH allowed from your IP only.
2. Confirm nginx answers on port 80 from your laptop.
3. Attach a 32 GB data disk, mount it at `/data` with fstab, reboot, confirm it mounts.
4. Grow the data disk to 64 GB and extend the filesystem without unmounting.
5. Break SSH on purpose: `sudo ufw default deny incoming && sudo ufw enable` without allowing SSH. Your session drops.
6. Recover with Run Command (`ufw disable`), then SSH in.
7. Add `/dev/sdz1 /broken ext4 defaults 0 2` to `/etc/fstab` (no `nofail`), reboot, and read the failure in boot diagnostics.
8. Fix it through the Serial Console (Chapter 22).
9. Take a snapshot of the OS disk.
10. Delete the resource group.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| SSH times out | NSG rule missing or wrong source IP, VM stopped. | `az network nic list-effective-nsg`, check `$MYIP` has not changed. |
| `Permission denied (publickey)` | Wrong user or key. | Use the admin username you set. `az vm user update` to add a key. |
| Run Command hangs or fails | Azure Linux agent not running or cannot reach `168.63.129.16`. | Serial Console, check `waagent.log`. |
| Serial Console shows no login prompt | Boot diagnostics off, or stuck earlier in boot. | Enable boot diagnostics. Read the serial log. |
| Data on `/mnt` gone after deallocate | Temporary disk. | Store data on a managed data disk. |
| `SkuNotAvailable` when creating or resizing | Size not available in that region or zone. | `az vm list-skus -l eastus --size Standard_B -o table`, pick another size or region. |

## Next

[20. Linux on AWS](../20-linux-on-aws/README.md)
