# Diagrams

The PNG files in this folder are used by the chapters. Each one has an editable source in [`src/`](src/), saved in draw.io format.

To change a diagram, open the `.drawio` file in [draw.io](https://app.diagrams.net) (File > Open from > Device) or in the draw.io desktop app and save it. Then regenerate the PNGs:

```bash
bash scripts/render-diagrams.sh
```

The script exports every file in `images/src/` with the draw.io web app in headless Chromium (Playwright), at 200% zoom on a white background. It needs `git`, `node`, `npm` and `python3`. You can also export by hand from draw.io: File > Export as > PNG, zoom 200%, then replace the PNG with the same name.

| Diagram | Used in |
|---|---|
| [00-learning-path.png](00-learning-path.png) | [README](../README.md) |
| [01-linux-layers.png](01-linux-layers.png) | [01. Linux Fundamentals](../01-linux-fundamentals/README.md) |
| [07-permissions.png](07-permissions.png) | [07. Permissions and Ownership](../07-permissions-and-ownership/README.md) |
| [12-storage-layers.png](12-storage-layers.png) | [12. Storage and Filesystems](../12-storage-and-filesystems/README.md) |
| [13-request-path.png](13-request-path.png) | [13. Networking](../13-networking/README.md) |
| [14-ssh-keys.png](14-ssh-keys.png) | [14. SSH](../14-ssh/README.md) |
| [18-cloud-init.png](18-cloud-init.png) | [18. cloud-init and Metadata](../18-cloud-init-and-metadata/README.md) |
| [19-azure-lab.png](19-azure-lab.png) | [19. Linux on Azure](../19-linux-on-azure/README.md) |
| [20-aws-lab.png](20-aws-lab.png) | [20. Linux on AWS](../20-linux-on-aws/README.md) |
| [21-gcp-lab.png](21-gcp-lab.png) | [21. Linux on Google Cloud](../21-linux-on-gcp/README.md) |
| [22-ssh-troubleshooting.png](22-ssh-troubleshooting.png) | [22. Troubleshooting](../22-troubleshooting/README.md#cannot-connect-with-ssh) |
| [22-boot-recovery.png](22-boot-recovery.png) | [22. Troubleshooting](../22-troubleshooting/README.md#server-does-not-boot-after-an-fstab-change) |
| [24-capstone.png](24-capstone.png) | [24. Capstone Project](../24-capstone-project/README.md) |
