# Rocky Linux 10.2 minimal kickstart for unattended install
# Used by provision-vm.sh for TASK-0003 VM testing

# Keyboard and language
keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8

# Network
network --bootproto=dhcp --device=eth0 --activate --onboot=yes

# Root password locked — VM accessed via SSH key injection only
rootpw --locked

# Firewall - disabled for testing
firewall --disabled

# SELinux - permissive for testing
selinux --permissive

# Reboot after installation
reboot

# System authorization
auth --enableshadow --passalgo=sha512

# Disable firstboot
firstboot --disable

# System timezone
timezone UTC --isUtc

# System bootloader configuration
bootloader --location=mbr --boot-drive=vda

# Partition clearing information
clearpart --all --initlabel

# Disk partitioning information
part / --fstype="xfs" --grow --size=1

%packages
@^minimal-environment
dnf
openssh-server
curl
wget
%end
