#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="openstack-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

BASE_DIR=$PWD

fatal() {
  echo "FATAL ERROR: $*" >&2
  exit 2
}

run_step() {
    NAME=$1
    SCRIPT=$2

    echo ">>> $NAME"

    if ! bash "$SCRIPT"; then
        fatal "$NAME failed"
    fi
}

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo "[ $CURRENT_STEP / $TOTAL_STEPS ] $1"
}

TOTAL_STEPS=11
CURRENT_STEP=0

source openstack.conf
source /etc/os-release

if [ "$EUID" -ne 0 ]; then
    echo "Run as root"
    exit 1
fi

cp openstack.conf scripts/openstack.conf

step "Prerequisites"
run_step "Prereqs" scripts/prereqs.sh

step "RabbitMQ"
run_step "RabbitMQ" scripts/rabbitmq.sh

step "MariaDB"
run_step "MariaDB" scripts/mariadb.sh

step "Keystone"
run_step "Keystone" scripts/keystone.sh

step "Glance"
run_step "Glance" scripts/glance.sh

if [ "${INSTALL_CINDER:-no}" = "yes" ]; then
    step "Cinder Storage"
    run_step "Cinder Storage" scripts/cinder-storage.sh

    step "Cinder Controller"
    run_step "Cinder Controller" scripts/cinder.sh
fi

step "Placement"
run_step "Placement" scripts/placement.sh

step "Nova"
run_step "Nova" scripts/nova.sh

step "Nova Compute"
run_step "Nova Compute" scripts/nova-compute.sh

step "Neutron"
run_step "Neutron" scripts/neutron.sh

step "Horizon"
run_step "Horizon" scripts/horizon.sh

# ----------------- FINALE INSTALLAZIONE -----------------
echo
echo "*** OpenStack installation Successful ***"
echo
echo "OpenStack installation Info"
echo "+-------------------------------------------------------------------------------------------------------------+"
echo "|    The keystone credentials RC files are stored in the /root directory                                        |"
echo "|    The admin password is '$ADMIN_PASSWORD'                                                                  |"
echo "|    The demo password is '$DEMO_PASSWORD'                                                                    |"
echo "|    Keystone is serving at http://$HOST_IP:5000/                                                             |"
echo "|                                                                                                             |"
echo "|    The Horizon dashboard is available at http://$HOST_IP/dashboard                                          |"
echo "|                                                                                                             |"
echo "|    The password for all services is '$SERVICE_PASSWORD', The password for all databases is '$DATABASE_PASSWORD' |"
echo "+-------------------------------------------------------------------------------------------------------------+"
echo
echo "System Info"
echo "+-------------------------------------------------------------------------------------------------------------+"
echo "|    Linux Distro: $NAME                                                                                      |"
echo "|    Version: $VERSION $VERSION_CODENAME                                                                      |"
echo "+-------------------------------------------------------------------------------------------------------------+"
exit 0
