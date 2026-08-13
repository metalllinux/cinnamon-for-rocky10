#!/bin/bash
# First-boot setup: enable SSH root login, disable firewall
sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl disable firewalld 2>/dev/null || true
systemctl stop firewalld 2>/dev/null || true
systemctl restart sshd 2>/dev/null || true
# Mark first boot as done
touch /var/run/first-boot-done
systemctl disable first-boot-setup.service 2>/dev/null || true
