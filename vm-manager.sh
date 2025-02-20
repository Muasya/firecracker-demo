#!/bin/bash
set -euo pipefail

# Configuration and utilities
VM_ROOT="/var/lib/firecracker-vms"
RESOURCES_DIR="${VM_ROOT}/resources"
LOG_DIR="${VM_ROOT}/logs"

# Generate a unique VM ID (UUID v4)
generate_vm_id() {
    python3 -c 'import uuid; print(str(uuid.uuid4()))'
}

# Setup required directories and permissions
setup_vm_environment() {
    mkdir -p "${VM_ROOT}/"{resources,logs,sockets,rootfs}
    chmod 755 "${VM_ROOT}"
}

# One-time system setup
system_setup() {
    # Load KVM module
    modprobe kvm_intel || true
    
    # System configurations for networking
    sysctl -w net.ipv4.conf.all.forwarding=1
    sysctl -w net.ipv4.netfilter.ip_conntrack_max=99999999
    sysctl -w net.ipv4.neigh.default.gc_thresh1=1024
    sysctl -w net.ipv4.neigh.default.gc_thresh2=2048
    sysctl -w net.ipv4.neigh.default.gc_thresh3=4096
    
    # Ensure resources exist
    ensure_resources
}

# Network setup for a specific VM
setup_network() {
    local vm_id=$1
    local tap_dev="tap-${vm_id:0:8}" # Use first 8 chars of UUID for tap device
    
    ip link del "$tap_dev" 2> /dev/null || true
    ip tuntap add dev "$tap_dev" mode tap
    sysctl -w net.ipv4.conf.${tap_dev}.proxy_arp=1 > /dev/null
    sysctl -w net.ipv6.conf.${tap_dev}.disable_ipv6=1 > /dev/null
    
    # Generate unique IP within private range
    local network_id=$(echo "$vm_id" | md5sum | head -c 4)
    local host_octet=$((0x$network_id % 252 + 1))
    local tap_ip="172.16.${host_octet}.1"
    local vm_ip="172.16.${host_octet}.2"
    
    ip addr add "${tap_ip}/30" dev "$tap_dev"
    ip link set dev "$tap_dev" up
    
    echo "${vm_ip}:${tap_ip}:${tap_dev}"
}

launch_vm() {
    local vm_id=$(generate_vm_id)
    local mem_size=${1:-128}
    local vcpus=${2:-1}
    local name=${3:-"vm-${vm_id:0:8}"}
    
    local socket_path="${VM_ROOT}/sockets/${vm_id}.sock"
    local log_path="${LOG_DIR}/${vm_id}.log"
    local metadata_path="${VM_ROOT}/metadata/${vm_id}.json"
    
    # Setup networking
    local network_info
    network_info=$(setup_network "$vm_id")
    local vm_ip=${network_info%%:*}
    local tap_ip=${network_info#*:}
    local tap_dev=${network_info##*:}
    
    # Start Firecracker
    firecracker --api-sock "$socket_path" --id "$name" >> "$log_path" &
    
    # Wait for API socket
    while [ ! -e "$socket_path" ]; do
        sleep 0.01s
    done
    
    # Configure VM via API
    configure_vm "$socket_path" "$vm_id" "$mem_size" "$vcpus" "$vm_ip" "$tap_ip" "$tap_dev"
    
    # Save metadata
    cat > "$metadata_path" <<EOF
{
    "id": "$vm_id",
    "name": "$name",
    "ip": "$vm_ip",
    "tap_device": "$tap_dev",
    "created": "$(date -Iseconds)",
    "mem_size": "$mem_size",
    "vcpus": "$vcpus"
}
EOF
    
    echo "$vm_id"
}

stop_vm() {
    local vm_id=$1
    local socket_path="${VM_ROOT}/sockets/${vm_id}.sock"
    local metadata_path="${VM_ROOT}/metadata/${vm_id}.json"
    
    if [ -f "$metadata_path" ]; then
        local tap_dev=$(jq -r .tap_device "$metadata_path")
        ip link del "$tap_dev" 2> /dev/null || true
    fi
    
    if [ -S "$socket_path" ]; then
        curl --unix-socket "$socket_path" -X PUT "http://localhost/actions" \
             -H "Content-Type: application/json" \
             -d '{"action_type": "SendCtrlAltDel"}'
        rm -f "$socket_path"
    fi
    
    # Cleanup metadata
    rm -f "$metadata_path"
}

# Node.js integration helpers
list_vms() {
    find "${VM_ROOT}/metadata" -name "*.json" -exec cat {} \; | jq -s '.'
}

get_vm_info() {
    local vm_id=$1
    local metadata_path="${VM_ROOT}/metadata/${vm_id}.json"
    if [ -f "$metadata_path" ]; then
        cat "$metadata_path"
    else
        echo "{}"
    fi
}

# Main entrypoint
case ${1:-help} in
    "init")
        setup_vm_environment
        system_setup
        ;;
    "start")
        launch_vm "${2:-128}" "${3:-1}" "${4:-}"
        ;;
    "stop")
        stop_vm "$2"
        ;;
    "list")
        list_vms
        ;;
    "info")
        get_vm_info "$2"
        ;;
    *)
        echo "Usage: $0 {init|start|stop|list|info} [args...]"
        exit 1
        ;;
esac