## SSH Access to VMs

Each VM is accessible via SSH using generated key pairs:

1. Launch a single VM:
```bash
./launch-a-single-vm.sh 1

# Find SSH details in vm-details/metrics/vm-1.json
# Connect using the provided SSH command
## Usage

```bash
# Launch VM #5
./launch-a-single-vm.sh 5

# Check VM details
cat ./vm-details/metrics/vm-5.json

# SSH into VM
ssh -i ./vm-details/ssh-keys/vm-5 root@169.254.x.x