#!/bin/bash
set -euo pipefail

# Configuration variables
FC_BINARY="${PWD}/resources/firecracker"
RO_DRIVE="${PWD}/resources/rootfs.ext4"
KERNEL="${PWD}/resources/vmlinux"
NETWORK_SETUP="${PWD}/scripts/setup-tap-with-id.sh"

# Default kernel boot arguments
KERNEL_BOOT_ARGS="console=ttyS0 reboot=k panic=1 pci=off nomodules i8042.nokbd i8042.noaux ipv6.disable=1"

function setup_network() {
    local vm_id=$1
    local tap_dev="fc-${vm_id}-tap0"
    
    # Create and configure TAP device
    ip link del "$tap_dev" 2> /dev/null || true
    ip tuntap add dev "$tap_dev" mode tap
    sysctl -w net.ipv4.conf.${tap_dev}.proxy_arp=1 > /dev/null
    sysctl -w net.ipv6.conf.${tap_dev}.disable_ipv6=1 > /dev/null
    
    # Calculate IP addresses
    local fc_ip="$(printf '169.254.%s.%s' $(((4 * vm_id + 1) / 256)) $(((4 * vm_id + 1) % 256)))"
    local tap_ip="$(printf '169.254.%s.%s' $(((4 * vm_id + 2) / 256)) $(((4 * vm_id + 2) % 256)))"
    
    # Configure TAP device IP
    ip addr add "${tap_ip}/30" dev "$tap_dev"
    ip link set dev "$tap_dev" up
    
    echo "${fc_ip}:${tap_ip}"
}

function launch_vm() {
    local vm_id=$1
    local mem_size=${2:-128}  # Default to 128MB RAM
    local vcpus=${3:-1}      # Default to 1 vCPU
    
    local api_socket="/tmp/firecracker-${vm_id}.sock"
    local logfile="${PWD}/output/fc-${vm_id}-log"
    
    # Setup networking
    local ips
    ips=$(setup_network "$vm_id")
    local fc_ip=${ips%:*}
    local tap_ip=${ips#*:}
    
    # Update kernel boot args with networking
    local boot_args="${KERNEL_BOOT_ARGS} ip=${fc_ip}::${tap_ip}:255.255.255.252::eth0:off"
    
    # Start Firecracker
    rm -f "$api_socket"
    "${FC_BINARY}" --api-sock "$api_socket" --id "${vm_id}" >> "$logfile" &
    
    # Wait for API socket
    while [ ! -e "$api_socket" ]; do
        sleep 0.01s
    done
    
    # Configure VM
    curl --unix-socket "$api_socket" -X PUT "http://localhost/machine-config" \
         -H "Content-Type: application/json" \
         -d "{\"vcpu_count\": ${vcpus}, \"mem_size_mib\": ${mem_size}}"
         
    # Configure boot source
    curl --unix-socket "$api_socket" -X PUT "http://localhost/boot-source" \
         -H "Content-Type: application/json" \
         -d "{\"kernel_image_path\": \"${KERNEL}\", \"boot_args\": \"${boot_args}\"}"
    
    # Configure root drive
    curl --unix-socket "$api_socket" -X PUT "http://localhost/drives/1" \
         -H "Content-Type: application/json" \
         -d "{\"drive_id\": \"1\", \"path_on_host\": \"${RO_DRIVE}\", \"is_root_device\": true, \"is_read_only\": true}"
    
    # Configure network
    local fc_mac="$(printf '02:FC:00:00:%02X:%02X' $((vm_id / 256)) $((vm_id % 256)))"
    curl --unix-socket "$api_socket" -X PUT "http://localhost/network-interfaces/1" \
         -H "Content-Type: application/json" \
         -d "{\"iface_id\": \"1\", \"guest_mac\": \"${fc_mac}\", \"host_dev_name\": \"fc-${vm_id}-tap0\"}"
    
    # Start VM
    curl --unix-socket "$api_socket" -X PUT "http://localhost/actions" \
         -H "Content-Type: application/json" \
         -d "{\"action_type\": \"InstanceStart\"}"
         
    echo "VM ${vm_id} started with IP ${fc_ip}"
    echo "You can connect using: ssh -i resources/rootfs.id_rsa root@${fc_ip}"
}

function stop_vm() {
    local vm_id=$1
    local api_socket="/tmp/firecracker-${vm_id}.sock"
    
    if [ -S "$api_socket" ]; then
        curl --unix-socket "$api_socket" -X PUT "http://localhost/actions" \
             -H "Content-Type: application/json" \
             -d "{\"action_type\": \"SendCtrlAltDel\"}"
        rm -f "$api_socket"
    fi
    
    # Cleanup network
    ip link del "fc-${vm_id}-tap0" 2> /dev/null || true
}

# Main script
command=$1
shift

case $command in
    "start")
        vm_id=$1
        mem_size=${2:-128}
        vcpus=${3:-1}
        launch_vm "$vm_id" "$mem_size" "$vcpus"
        ;;
    "stop")
        vm_id=$1
        stop_vm "$vm_id"
        ;;
    *)
        echo "Usage: $0 start <vm_id> [mem_size_mb] [vcpus]"
        echo "       $0 stop <vm_id>"
        exit 1
        ;;
esac