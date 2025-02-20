# a simplified and more manageable script for launching individual Firecracker VMs on demand. Here's how to use it:

First, make sure you have the required resources:

```resources/firecracke``` binary
```resources/rootfs.ext4``` root filesystem
```resources/vmlinux kernel``` image
```resources/rootfs.id_rsa``` SSH key for accessing VMs


# Create necessary directories:

``` bash
mkdir -p output
chmod +x firecracker-manager.sh
```

# Launch a VM:

``` bash
# Basic usage (1 vCPU, 128MB RAM)
sudo ./firecracker-manager.sh start 1

# Custom configuration (2 vCPUs, 256MB RAM)
sudo ./firecracker-manager.sh start 1 256 2
```

# Stop a VM:

``` bash
sudo ./firecracker-manager.sh stop 1
```