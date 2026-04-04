# Debian OpenStack Installer

### A Devstack alternative to quickly deploy a test OpenStack environment on Debian-based distributions

Debian OpenStack Installer is a set of SH scripts that allows deploying a minimal OpenStack environment on Debian-based systems.
It can install OpenStack **on a single node**, automatically configuring the core services.

Each script is responsible for configuring a single service.

---

## Requirements

### Supported Distros

* Ubuntu
* Pop!_OS
* Q4OS
* SparkyLinux
* Zorin OS
* Kali Linux
* Linux Mint
* Elementary OS
* Any Debian-based distro with Python3+

### Unsupported Distros

* CentOS
* Fedora
* OpenSUSE
* Any non-Debian-based distro

---

### Minimum requirements

* RAM: 4 GB
* CPU: 2 cores
* Storage: 10 GB

### Recommended requirements

* RAM: 8 GB
* CPU: 4 cores
* Storage: 20 GB

---

## Important Note

**This installer does not support Netplan.**
You must use `ifupdown` to properly configure networking and Open vSwitch (OVS) bridges for Neutron.

---

## Disable Netplan and enable ifupdown

```bash
# Remove Netplan
apt remove netplan.io -y

# Install ifupdown
apt install ifupdown -y

# Stop systemd network manager
systemctl disable systemd-networkd
systemctl stop systemd-networkd

# Backup Netplan configuration files
mv /etc/netplan/*.yaml /etc/netplan/*.yaml.bak
```

### Configure a static IP for your host's public interface

Replace `YOUR_PUBLIC_INTERFACE` with your real interface name (e.g., ens33).
Replace `<HOST_IP>`, `<HOST_NETMASK>`, and `<HOST_GATEWAY>` with the correct values for your network.

```bash
cat << EOF > /etc/network/interfaces.d/network
auto lo
iface lo inet loopback

auto YOUR_PUBLIC_INTERFACE
iface YOUR_PUBLIC_INTERFACE inet static
    address <HOST_IP>
    netmask <HOST_NETMASK>
    gateway <HOST_GATEWAY>
    dns-nameservers 8.8.8.8 1.1.1.1
EOF

# Restart networking
systemctl restart networking
```

---

## OpenStack Installation

1. Update the system:

```bash
sudo su
apt update -y && apt upgrade -y
```

2. Install Git (if not already installed):

```bash
apt install git -y
```

3. Clone the repository:

```bash
cd /root
git clone https://github.com/Sorecchione07435/Debian-OpenStack-Installer.git
cd Debian-OpenStack-Installer/
```

4. Configure `openstack.conf`:

* Set your public interface (`YOUR_PUBLIC_INTERFACE`)
* Enter host IP, netmask, and gateway
* Enter passwords for admin, demo, services, databases, and RabbitMQ
* Select the OpenStack release

5. Make the main script executable:

```bash
chmod +x openstack-install.sh
```

6. Run the installation:

```bash
./openstack-install.sh
```

> Installation may take a few minutes depending on your machine.

---

## Installed Services

* Keystone
* Glance
* Cinder (Optional)
* Placement
* Nova
* Neutron (with OVS bridges configured)
* Horizon

---

## Access OpenStack

After installation:

* Horizon Dashboard: `http://<HOST_IP>/dashboard`
* Admin username: as configured in `openstack.conf`
* Admin password: as configured in `openstack.conf`

---

## Networks and Images

If the public or internal networks are not created correctly, or the Cirros image is missing, you can run:

```bash
./finalize.sh
```

---

## Limitations

* This is **a test environment**; not for production use.
* Network connectivity may not always be fully stable for complex scenarios.
* Requires `ifupdown` and **does not support Netplan**.
* OVS bridges are created for the host’s public interface; always replace `YOUR_PUBLIC_INTERFACE` with your real interface.

---

## Conclusion

Once installation is complete, you can create instances, upload images, and experiment with OpenStack services.
