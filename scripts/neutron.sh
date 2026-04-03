#!/usr/bin/env bash
# Configure the Networking service (Neutron) with OVS bridges

set -o xtrace
set -e

source openstack.conf

# Config files
conf_file=/etc/neutron/neutron.conf
conf_ml2=/etc/neutron/plugins/ml2/ml2_conf.ini
conf_openvswitch=/etc/neutron/plugins/ml2/openvswitch_agent.ini
conf_dhcp_agent=/etc/neutron/dhcp_agent.ini
conf_metadata_agent=/etc/neutron/metadata_agent.ini
conf_l3_agent=/etc/neutron/l3_agent.ini
conf_nova=/etc/nova/nova.conf

# Retry function
exec_with_retry () {
    local MAX_RETRIES=$1
    local INTERVAL=$2
    local COUNTER=0
    while [ $COUNTER -lt $MAX_RETRIES ]; do
        local EXIT=0
        eval '${@:3}' || EXIT=$?
        if [ $EXIT -eq 0 ]; then
            return 0
        fi
        let COUNTER=COUNTER+1
        if [ -n "$INTERVAL" ]; then
            sleep $INTERVAL
        fi
    done
    return $EXIT
}

# Install packages
install_pkgs() {
    apt update
    apt install -y neutron-server neutron-plugin-ml2 neutron-openvswitch-agent \
        neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent openvswitch-switch
}

# Configure OVS bridges
conf_openvswitch_bridges() {
    INTERFACES_FILE=/etc/network/interfaces.d/openvswitch

    ip addr flush dev $PUBLIC_BRIDGE_INTERFACE
    ip link set $PUBLIC_BRIDGE_INTERFACE down
    ovs-vsctl del-br $PUBLIC_BRIDGE || true

    ovs-vsctl add-br $PUBLIC_BRIDGE
    ovs-vsctl add-port $PUBLIC_BRIDGE $PUBLIC_BRIDGE_INTERFACE
    ip link set $PUBLIC_BRIDGE up
    ip addr add $HOST_IP/$HOST_IP_CIDR dev $PUBLIC_BRIDGE
    ip route add default via $PUBLIC_SUBNET_GATEWAY

    # Create OVS bridges via interfaces file
    if [ ! -f "$INTERFACES_FILE" ]; then
        cat << EOF > "$INTERFACES_FILE"
auto lo
iface lo inet loopback

# Physical interface (no IP)
auto $PUBLIC_BRIDGE_INTERFACE
iface $PUBLIC_BRIDGE_INTERFACE inet manual
    ovs_type OVSPort
    ovs_bridge $PUBLIC_BRIDGE

# Public OVS bridge
auto $PUBLIC_BRIDGE
iface $PUBLIC_BRIDGE inet static
    address $HOST_IP
    netmask $HOST_IP_NETMASK
    gateway $PUBLIC_SUBNET_GATEWAY
    dns-nameservers $PUBLIC_SUBNET_DNS_SERVERS
    ovs_type OVSBridge
    ovs_ports $PUBLIC_BRIDGE_INTERFACE

# Internal OVS bridge (no IP)
auto $INTERNAL_BRIDGE
iface $INTERNAL_BRIDGE inet manual
    ovs_type OVSBridge
EOF
    fi

    # Restart networking
    systemctl disable systemd-networkd
    systemctl stop systemd-networkd
    systemctl enable networking
    systemctl restart networking
}

# Configure Neutron and ML2
conf_neutron() {
    crudini --set $conf_file database connection mysql+pymysql://neutron:$DATABASE_PASSWORD@$HOST_IP/neutron

    crudini --set $conf_file DEFAULT core_plugin ml2
    crudini --set $conf_file DEFAULT transport_url rabbit://openstack:$RABBITMQ_PASSWORD@$HOST_IP
    crudini --set $conf_file DEFAULT auth_strategy keystone
    crudini --set $conf_file DEFAULT service_plugins router

    crudini --set $conf_file keystone_authtoken www_authenticate_uri http://$HOST_IP:5000
    crudini --set $conf_file keystone_authtoken auth_url http://$HOST_IP:5000
    crudini --set $conf_file keystone_authtoken memcached_servers 127.0.0.1:11211
    crudini --set $conf_file keystone_authtoken auth_type password
    crudini --set $conf_file keystone_authtoken project_domain_name default
    crudini --set $conf_file keystone_authtoken user_domain_name default
    crudini --set $conf_file keystone_authtoken project_name service
    crudini --set $conf_file keystone_authtoken username neutron
    crudini --set $conf_file keystone_authtoken password $SERVICE_PASSWORD

    crudini --set $conf_file DEFAULT notify_nova_on_port_status_changes true
    crudini --set $conf_file DEFAULT notify_nova_on_port_data_changes true

    crudini --set $conf_file nova auth_url http://$HOST_IP:5000
    crudini --set $conf_file nova auth_type password
    crudini --set $conf_file nova project_domain_name default
    crudini --set $conf_file nova user_domain_name default
    crudini --set $conf_file nova region_name RegionOne
    crudini --set $conf_file nova project_name service
    crudini --set $conf_file nova username nova
    crudini --set $conf_file nova password $SERVICE_PASSWORD

    crudini --set $conf_file oslo_concurrency lock_path /var/lib/neutron/tmp

    crudini --set $conf_ml2 ml2 type_drivers flat,vlan,vxlan,local
    crudini --set $conf_ml2 ml2 tenant_network_types flat,vlan,local
    crudini --set $conf_ml2 ml2 extension_drivers port_security
    crudini --set $conf_ml2 ml2_type_flat flat_networks public,internal
    crudini --set $conf_ml2 securitygroup enable_ipset true
    crudini --set $conf_ml2 ml2 mechanism_drivers openvswitch

    crudini --set $conf_openvswitch ovs integration_bridge br-int
    crudini --set $conf_openvswitch ovs bridge_mappings public:$PUBLIC_BRIDGE,internal:$INTERNAL_BRIDGE
    crudini --set $conf_openvswitch securitygroup enable_security_group true
    crudini --set $conf_openvswitch firewall_driver openvswitch

    crudini --set $conf_dhcp_agent DEFAULT interface_driver openvswitch
    crudini --set $conf_dhcp_agent DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
    crudini --set $conf_dhcp_agent DEFAULT enable_isolated_metadata true

    crudini --set $conf_metadata_agent DEFAULT nova_metadata_host $HOST_IP
    crudini --set $conf_metadata_agent DEFAULT metadata_proxy_shared_secret $SERVICE_PASSWORD

    crudini --set $conf_l3_agent DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
    crudini --set $conf_l3_agent DEFAULT external_network_bridge ""
    crudini --set $conf_l3_agent DEFAULT use_namespaces true
    crudini --set $conf_l3_agent DEFAULT debug true

    crudini --set $conf_nova neutron auth_url http://$HOST_IP:5000
    crudini --set $conf_nova neutron auth_type password
    crudini --set $conf_nova neutron project_domain_name default
    crudini --set $conf_nova neutron user_domain_name default
    crudini --set $conf_nova neutron region_name RegionOne
    crudini --set $conf_nova neutron project_name service
    crudini --set $conf_nova neutron username neutron
    crudini --set $conf_nova neutron password $SERVICE_PASSWORD
    crudini --set $conf_nova neutron service_metadata_proxy true
    crudini --set $conf_nova neutron metadata_proxy_shared_secret $SERVICE_PASSWORD

    su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

    exec_with_retry 15 0 systemctl restart nova-api
    exec_with_retry 15 0 systemctl restart neutron-server neutron-openvswitch-agent neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent nova-compute
}

# Create networks in OpenStack
create_networks() {
    export OS_USERNAME=admin
    export OS_PASSWORD=$ADMIN_PASSWORD
    export OS_PROJECT_NAME=admin
    export OS_USER_DOMAIN_NAME=Default
    export OS_PROJECT_DOMAIN_NAME=Default
    export OS_AUTH_URL=http://$HOST_IP:5000/v3
    export OS_IDENTITY_API_VERSION=3

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

# Run functions
install_pkgs
conf_openvswitch_bridges
conf_neutron
set +e
create_networks

# Final note
NORMAL=$(tput sgr0)
YELLOW=$(tput setaf 3)
echo "${YELLOW}NOTE: If the networks or cirros image did not create successfully, try running the separate finalize.sh script${NORMAL}"

echo "Done!"
exit 0
