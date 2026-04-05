#!/usr/bin/env bash
# Configure the Block Storage service (Cinder) (Storage Node)

set -o xtrace
set -e

source openstack.conf

LOOP_DEV="/dev/${CINDER_VOLUME_LVM_PHYSICAL_PV_LOOP_PATH}"
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
    apt install -y cinder-volume tgt
}

setup_lvm(){

    LOOP_DEV="${CINDER_VOLUME_LVM_PHYSICAL_PV_LOOP_NAME}"
    VG_NAME="cinder-volumes"

    mkdir -p /var/lib/cinder/images

    if [ ! -f "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH" ]; then
        # Creazione immagine LVM
        fallocate -l ${CINDER_VOLUME_LVM_IMAGE_SIZE_IN_GB}G "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH"

        id -u cinder &>/dev/null || useradd -r -s /bin/false cinder
        id -g cinder &>/dev/null || groupadd cinder

        chown cinder:cinder "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH"
        chmod 600 "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH"
    fi

    # Associa il loop device specificato
    if ! losetup "$LOOP_DEV" &>/dev/null; then
        losetup "$LOOP_DEV" "$CINDER_VOLUME_LVM_IMAGE_FILE_PATH"
    fi

    # LVM
    if ! pvs | grep -q "$LOOP_DEV"; then
        pvcreate "$LOOP_DEV"
    fi

    if ! vgs | grep -q "$VG_NAME"; then
        vgcreate "$VG_NAME" "$LOOP_DEV"
    fi
}

setup_iscsi(){

    echo 'include /var/lib/cinder/volumes/*' > /etc/tgt/conf.d/cinder.conf

}

setup_loopback_service(){
cat > /etc/systemd/system/cinder-loopback.service << EOF
[Unit]
Description=Cinder LVM loopback device
Before=cinder-volume.service tgt.service
DefaultDependencies=no
After=local-fs.target

[Service]
Type=oneshot

ExecStart=/bin/bash -c 'if ! losetup $LOOP_DEV | grep -q cinder-volumes.img; then /sbin/losetup $LOOP_DEV $CINDER_VOLUME_LVM_IMAGE_FILE_PATH; fi'
ExecStart=/sbin/vgchange -ay $VG_NAME

ExecStop=/sbin/vgchange -an $VG_NAME
ExecStop=/bin/bash -c 'if losetup $LOOP_DEV | grep -q cinder-volumes.img; then /sbin/losetup -d $LOOP_DEV; fi'

RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload  
}

finalize(){
    systemctl enable cinder-loopback.service

    exec_with_retry 15 3 systemctl restart tgt
    exec_with_retry 15 3 systemctl restart cinder-volume
    
    exec_with_retry 15 3 systemctl start cinder-loopback.service

    tgtadm --mode target --op show
}

install_pkgs
setup_lvm
setup_iscsi
setup_loopback_service
finalize

echo "Done!"
exit 0
