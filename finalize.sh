#!/usr/bin/env bash

set -o xtrace
set -e

BASE_DIR=$PWD
source openstack.conf

create_networks(){

   openstack network create --share --external \
        --provider-physical-network public \
        --provider-network-type flat public || true

    openstack subnet create --network public \
        --allocation-pool start=$PUBLIC_SUBNET_RANGE_START,end=$PUBLIC_SUBNET_RANGE_END \
        --dns-nameserver $PUBLIC_SUBNET_DNS_SERVERS \
        --gateway $PUBLIC_SUBNET_GATEWAY \
        --subnet-range $PUBLIC_SUBNET_CIDR \
        public_subnet || true

    openstack network create --share --provider-physical-network internal --provider-network-type flat internal 

    openstack subnet create --network internal \
        --subnet-range 10.0.0.0/24 \
        --gateway 10.0.0.1 \
        --allocation-pool start=10.0.0.10,end=10.0.0.200 \
        --dns-nameserver 8.8.8.8 internal_subnet || true

    openstack router create internal_router || true
    openstack router set internal_router --external-gateway public || true
    openstack router add subnet internal_router internal_subnet || true
}

upload_cirros_image(){

wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img

glance image-create --name "cirros" \
  --file cirros-0.4.0-x86_64-disk.img \
  --disk-format qcow2 --container-format bare \
  --visibility=public
  
  rm -rf $BASE_DIR/cirros-0.4.0-x86_64-disk.img

}


export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASSWORD
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://$HOST_IP:5000/v3
export OS_IDENTITY_API_VERSION=3

create_networks
upload_cirros_image

echo "Finalize Complete!"
exit 0
