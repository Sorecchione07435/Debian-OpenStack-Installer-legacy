#!/usr/bin/env bash
# Configure the Block Storage service (Cinder) (Storage Node)

set -o xtrace
set -e

source openstack.conf

VG_NAME="cinder-volumes"

exec_with_retry () {
    local MAX_RETRIES=$1
    local INTERVAL=$2
    local COUNTER=0
    while [ $COUNTER -lt $MAX_RETRIES ]; do
        local EXIT=0
        "${@:3}" || EXIT=$?
        if [ $EXIT -eq 0 ]; then
            return 0
        fi
        COUNTER=$((COUNTER + 1))
        if [ -n "$INTERVAL" ] && [ "$INTERVAL" -gt 0 ]; then
            sleep $INTERVAL
        fi
    done
    return $EXIT
}


install_pkgs(){
    apt install -y cinder-volume
}

setup_lvm(){

    mkdir -p /var/lib/cinder/images

    if [ ! -f "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH" ]; then
        #dd if=/dev/zero of="$CINDER_VOLUME_LVM_IMAGE_FILE_PATH" bs=1G count=$CINDER_VOLUME_LVM_IMAGE_SIZE_IN_GB
        fallocate -l ${CINDER_VOLUME_LVM_IMAGE_SIZE_IN_GB}G "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH"

        id -u cinder &>/dev/null || useradd -r -s /bin/false cinder
        id -g cinder &>/dev/null || groupadd cinder

        chown cinder:cinder "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH"
        chmod 600 "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH"
    fi 

    if losetup -a | grep -q "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH"; then
        LOOP_DEV=$(losetup -a | grep "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH" | cut -d: -f1)
    else
        LOOP_DEV=$(losetup -f --show "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH")
    fi

    if ! pvs | grep -q "$LOOP_DEV"; then
        pvcreate $LOOP_DEV
    fi

    if ! vgs | grep -q "$VG_NAME"; then
        vgcreate $VG_NAME $LOOP_DEV
    fi

    if ! grep -q "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH" /etc/fstab; then
        echo "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH none loop defaults 0 0" >> /etc/fstab
    fi

}

finalize(){
    exec_with_retry 15 3 systemctl restart cinder-volume apache2
}

install_pkgs
setup_lvm
finalize

echo "Done!"
exit 0
