#!/bin/bash

set -e

# Base directories
BASE_DIR="./vm-details"
DIRS=(
    "configs"
    "ssh-keys"
    "rootfs"
    "logs"
    "metrics"
    "metadata"
)

generate_uuid() {
    python3 -c 'import uuid; print(uuid.uuid4())'
}

setup_directories() {
    for dir in "${DIRS[@]}"; do
        mkdir -p "${BASE_DIR}/${dir}"
    done
    touch "${BASE_DIR}/metadata/vm-mappings.json"
}

store_vm_mapping() {
    local vm_id=$1
    local uuid=$2
    local mapping_file="${BASE_DIR}/metadata/vm-mappings.json"
    
    # Create or update mapping
    if [ ! -s "$mapping_file" ]; then
        echo "{}" > "$mapping_file"
    fi
    
    # Add new mapping using jq
    jq --arg id "$vm_id" --arg uuid "$uuid" \
       '. + {($id): $uuid}' "$mapping_file" > "${mapping_file}.tmp" && \
    mv "${mapping_file}.tmp" "$mapping_file"
}

generate_ssh_key() {
    local uuid=$1
    local key_path="${BASE_DIR}/ssh-keys/${uuid}"
    
    if [[ ! -f "${key_path}" ]]; then
        ssh-keygen -t rsa -b 2048 -f "${key_path}" -N "" -C "vm-${uuid}"
    fi
    echo "${key_path}"
}

launch_vm() {
    local vm_id=$1
    local uuid=$(generate_uuid)
    store_vm_mapping "$vm_id" "$uuid"
    
    local ssh_key_path=$(generate_ssh_key "$uuid")
    
    # Generate VM config
    local config_file="${BASE_DIR}/configs/${uuid}.json"
    cat > "$config_file" << EOF
{
    "boot-source": {
        "kernel_image_path": "./vmlinux.bin",
        "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
    },
    "drives": [
        {
            "drive_id": "rootfs",
            "path_on_host": "./ubuntu-18.04.ext4",
            "is_root_device": true,
            "is_read_only": false
        }
    ],
    "network-interfaces": [
        {
            "iface_id": "eth0",
            "host_dev_name": "tap-${uuid:0:8}"
        }
    ],
    "machine-config": {
        "vcpu_count": 1,
        "mem_size_mib": 128,
        "ht_enabled": false
    }
}
EOF

    # Launch VM
    local api_socket="/tmp/firecracker-${uuid}.sock"
    local log_file="${BASE_DIR}/logs/${uuid}.log"
    
    # Setup network tap if not exists
    ./scripts/setup-network-taps.sh "${uuid:0:8}" 1
    
    # Start Firecracker
    rm -f "$api_socket"
    firecracker --api-sock "$api_socket" \
                --config-file "$config_file" \
                --log-path "$log_file" &
    
    # Wait for boot
    until grep "Guest-boot" "$log_file" 2>/dev/null; do
        sleep 0.1
    done
    
    # Get VM details
    local fc_ip="$(printf '169.254.%s.%s' $(((4 * vm_id + 1) / 256)) $(((4 * vm_id + 1) % 256)))"
    local boot_time=$(grep "Guest-boot" "$log_file" | cut -f2 -d'=' | tr -d ' ')
    
    # Save VM details
    cat > "${BASE_DIR}/metrics/${uuid}.json" << EOF
{
    "vm_id": "$vm_id",
    "uuid": "$uuid",
    "ip_address": "$fc_ip",
    "tap_device": "tap-${uuid:0:8}",
    "boot_time_ms": "$boot_time",
    "log_file": "$log_file",
    "api_socket": "$api_socket",
    "ssh_key": "$ssh_key_path",
    "ssh_command": "ssh -i ${ssh_key_path} root@${fc_ip}"
}
EOF

    echo "VM launched successfully."
    echo "VM ID: $vm_id"
    echo "UUID: $uuid"
    echo "Details saved to ${BASE_DIR}/metrics/${uuid}.json"
    echo "To SSH into VM: ssh -i ${ssh_key_path} root@${fc_ip}"
}

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq first."
    exit 1
fi

# Main
setup_directories

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <vm_id>"
    exit 1
fi

launch_vm "$1"