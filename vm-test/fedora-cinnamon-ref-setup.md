# Fedora 44 Cinnamon reference VM (`fedora-cinnamon-ref`)

This document records the setup process for `fedora-cinnamon-ref`, a libvirt domain on the
Team Chaotix host (Rocky Linux 10.2, libvirt/KVM). It is the golden reference for the
Cinnamon-for-Rocky-10 work, a complete stock Fedora 44 Cinnamon desktop against which the
packages built in this repo are compared. The sibling domain `rocky10-explore` (Rocky 10.2,
same host) follows the same pattern, but the details here are Fedora-specific.

Provisioning ran on 2026-08-31 and the finalized state was verified on 2026-09-01. Paths,
versions, and commands below are as executed on the host. The full provisioning record,
including the failed iterations, is in the Team Chaotix planning doc
`TASK-0018-vm-reference-explore-provisioning.md` in the `metalllinux/team-chaotix` repo.

## Why the Cinnamon Live ISO cannot be used

The first instinct is to install from `Fedora-Cinnamon-Live-44-1.7.x86_64.iso`. That image
cannot do unattended installs by design, and the block was verified from the mounted ISO. The
live rootfs installs through `/usr/sbin/liveinst`, which explicitly rejects kickstart. Passing
`inst.ks` or `ks=` fails with "Kickstart is not supported on Live ISO installs". The live image
also has no repo tree (no `repodata/`), so even a manual install has no package source on the
medium.

Fedora 44 spins ship live ISOs only, with no per-spin DVD or netinst. The working strategy is
the generic `Everything` netinst ISO, booted through its pxeboot files, with the kickstart on a
small seed ISO and the full package set from a network repo. The Cinnamon desktop is pulled in
by group name from the network repo.

## Media

No ISO surgery. Four pieces.

1. **The netinst ISO.** `Fedora-Everything-netinst-x86_64-44-1.7.iso` (1.1 GiB) from the Fedora
   release tree, with the PGP-signed `Fedora-Everything-44-1.7-x86_64-CHECKSUM` in the same
   directory.
   `https://download.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/iso/`
   The verified sha256 is `bd285201494dd0ba09b54d05ac707de1401668b8512a573edb5922dcf9d7067e`.
   Keep the ISO at `/home/howard/ISOs/`.

   Verify the download before booting it. Compute the sha256 and compare it to the printed value
   (and check the PGP signature against the `CHECKSUM` file if the Fedora release key is
   trusted). The recorded run matched before the pxeboot extraction.

   ```
   sha256sum /home/howard/ISOs/Fedora-Everything-netinst-x86_64-44-1.7.iso
   ```

2. **The pxeboot kernel and initrd.** Mount the netinst ISO read-only at any mount point and copy
   `images/pxeboot/vmlinuz` and `images/pxeboot/initrd.img` to
   `/home/howard/ISOs/fc-pxeboot/`, keeping the file names. The install-boot XML (below) points
   at those two files. QEMU loads the `-kernel` file directly from the host and hands it to the
   guest as the boot image, outside the firmware boot process, and re-loads it on every guest
   reset. The netinst pxeboot copy the install actually used is the one in `fc-pxeboot/`. Its
   `vmlinuz` is hash-equal to the ISO's `images/pxeboot/vmlinuz`.

   A second directory, `/home/howard/ISOs/fc-inst/`, also exists on the host. It is not the
   install pxeboot. During the repair work in the Finalization section, the installed system's
   own kernel and initramfs were copied into `fc-inst/` and the repair-boot XML pointed at
   them, and that is the only reason `fc-inst/` exists. It no longer holds the netinst anaconda
   kernel, so do not reuse it to re-run the install. Re-extract from the ISO into `fc-pxeboot/`
   if the installer is needed again.

3. **The kickstart seed ISO.** A plain data ISO with one file, `ks.cfg`, at the root. The
   recorded final kickstart is `/tmp/opencode/vm18/fc-ks-v4.cfg`, copied into the seed directory
   `/tmp/opencode/vm18/seed2/` as `ks.cfg` (the two files are byte-identical). Build the ISO
   with genisoimage and label it `fedora-ks`.

   ```
   cp /tmp/opencode/vm18/fc-ks-v4.cfg /tmp/opencode/vm18/seed2/ks.cfg
   genisoimage -output /home/howard/ISOs/fc-seed4.iso -V fedora-ks -r -J -quiet /tmp/opencode/vm18/seed2/
   ```

   Do not reuse the earlier `/tmp/opencode/vm18/fc-seed/` directory. Its `ks.cfg` is an earlier
   iteration that ends in `reboot` and carries the `--sshkey` parse error, so burning it
   reproduces both recorded failures. The kernel command line finds the seed with
   `inst.ks=cdrom:/ks.cfg`. Anaconda scans the CDROMs for that path, and the stock netinst ISO
   does not ship a kickstart at the root, so only the seed matches.

4. **The network repo.** `https://mirrors.kernel.org/fedora/releases/44/Everything/x86_64/os/`
   is the full Everything repo (76354 packages as of 2026-08-31), and its comps data lists the
   `cinnamon-desktop` group. The kickstart declares it, which makes the install network-based.

## Host prep

The host needs `genisoimage` to build the seed ISO. On this Rocky 10 host it is the
`genisoimage` package (`dnf install genisoimage`); `xorriso` builds the same ISO if it is
already present.

The host's `/` has little free space (about 14G as of 2026-08-31) while `/home` has 648G, so
the disk and all install media live under `/home/howard`.

```
mkdir -p /home/howard/vm-disks
sudo qemu-img create -f qcow2 /home/howard/vm-disks/fedora-cinnamon-ref.qcow2 32G
```

Files under `/home` are not labeled for libvirt guest use. Pre-label every file the domain XML
references, or the domain start fails with SELinux denials on the disk and ISO paths.

```
sudo chcon -t svirt_image_t \
  /home/howard/vm-disks/fedora-cinnamon-ref.qcow2 \
  /home/howard/ISOs/Fedora-Everything-netinst-x86_64-44-1.7.iso \
  /home/howard/ISOs/fc-seed4.iso \
  /home/howard/ISOs/fc-pxeboot/vmlinuz \
  /home/howard/ISOs/fc-pxeboot/initrd.img
```

VNC port 5900 is already taken by the pre-existing `gdm-login-vm`, so this VM uses 5901.
Networking is the default libvirt network (`default`, bridge `virbr0`, 192.168.122.1/24) with
DHCP, which gives the VM a 192.168.122.x address with no firewall or NAT changes.

## Kickstart

The final kickstart is the recorded `/tmp/opencode/vm18/fc-ks-v4.cfg`, copied into the seed
directory as `ks.cfg` and burned into the seed ISO with the Media step 3 command. The two
public keys are the host's default `id_ed25519` (comment `sparky@team-chaotix-host`) and the
harness test key `~/.ssh/cinnamon-test-key` (comment `cinnamon-test`). Public keys only. No
password or private key appears anywhere in this process.

```
lang en_US.UTF-8
keyboard us
rootpw --lock
user --name howard --groups wheel --gecos "Howard"
network --bootproto dhcp
firewall --disabled
timezone UTC
selinux --enforcing
zerombr
clearpart --all --initlabel
autopart
bootloader --location=mbr
repo --name=fedora --baseurl=https://mirrors.kernel.org/fedora/releases/44/Everything/x86_64/os/ --cost=100
poweroff
%packages
@core
@cinnamon-desktop
gnome-terminal
openssh-server
%end
%post
# SSH keys (public only) for howard
mkdir -p /home/howard/.ssh
printf '%s\n' \
  '<public key with comment sparky@team-chaotix-host>' \
  '<public key with comment cinnamon-test>' \
  > /home/howard/.ssh/authorized_keys
chown -R howard:howard /home/howard/.ssh
chmod 700 /home/howard/.ssh
chmod 600 /home/howard/.ssh/authorized_keys
# user without --password may be PAM-locked ('!' in shadow), which blocks key login under UsePAM
sed -i 's/^\(howard:\)!\(.*\)$/\1*/' /etc/shadow
systemctl enable sshd
%end
```

**The `user` command has no `--sshkey` in Fedora 44.** The F44 pykickstart `user` command does
not accept `--sshkey` (verified in the pykickstart source in the install rootfs), so the first
iteration with inline `--sshkey` arguments failed to parse. The keys go into `%post` instead,
where `authorized_keys` is written with the ownership and permissions sshd requires.

**The shadow file fix is preventive.** A user created without `--password` can carry a `!` in
`/etc/shadow`, which PAM reads as a locked account, and sshd running under PAM then refuses key
login. The `sed` rewrites that field to `*`. This was not an observed failure in the recorded
run, and the line stays because the failure mode is silent.

**`poweroff`, not `reboot`.** QEMU re-runs the `-kernel` boot on every guest reset. With
`reboot`, Anaconda's final reboot restarts the pxeboot kernel and the kickstart, and `clearpart`
wipes the install that had finished. The recorded failure mode is an install loop, with the
disk found holding an empty `/boot` and an empty btrfs root (verified with qemu-nbd).
`poweroff` ends the install cleanly. The domain's `<on_poweroff>destroy` policy then tears the
VM down, and the finalization step redefines it without the kernel override.

**`repo` with `--cost=100`.** dnf assigns repos a default cost of 1000 and picks the lowest-cost
repo for a package available in more than one. Cost 100 puts the kernel.org mirror below that
default, so for a package present on both the mirror and the netinst medium, dnf takes the
mirror copy.

**`@cinnamon-desktop`** is the group id in the F44 comps data. The install completing from that
group, and the installed system running Cinnamon 6.6.7, confirm it.

**`firewall --disabled`.** The reference VM is isolated (behind the host NAT, SSH-key-only, no
outbound exposure), so the guest firewall is left off to keep the reference simple. A guest
firewall would not block key-based SSH, so re-enabling it is the safer default, and this line
should not be copied into a less isolated VM.

## Domain definition

Two XML states. One for the install, one final.

**Install boot.** The base domain plus three lines in `<os>` pointing at the extracted pxeboot
files.

```xml
<os>
  <type arch='x86_64' machine='pc-q35-rhel10.2.0'>hvm</type>
  <kernel>/home/howard/ISOs/fc-pxeboot/vmlinuz</kernel>
  <initrd>/home/howard/ISOs/fc-pxeboot/initrd.img</initrd>
  <cmdline>inst.ks=cdrom:/ks.cfg console=tty0,115200n8 console=ttyS0,115200n8 loglevel=8</cmdline>
</os>
```

The domain also carries the virtio disk plus two CDROM devices, the seed on `sda` and the
netinst on `sdb`. `console=ttyS0` makes the serial console (`virsh console`) work from the
first boot, so the whole install is observable without VNC.

**Final.** After the install, the persistent definition drops the kernel override and the
CDROMs. The parts that carry decisions.

```xml
<memory unit='KiB'>4194304</memory>
<vcpu placement='static'>4</vcpu>
...
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2' discard='unmap'/>
  <source file='/home/howard/vm-disks/fedora-cinnamon-ref.qcow2'/>
  <target dev='vda' bus='virtio'/>
  <boot order='1'/>
</disk>
...
<interface type='network'>
  <source network='default'/>
  <model type='virtio'/>
</interface>
...
  <graphics type='vnc' port='5901' autoport='no' listen='127.0.0.1'/>
...
<on_poweroff>destroy</on_poweroff>
<on_reboot>restart</on_reboot>
<on_crash>destroy</on_crash>
```

That is 4 GiB RAM, 4 vCPU, KVM with the pc-q35 machine type, a virtio disk with boot order 1, a
virtio NIC on the default network, and VNC on 5901 bound to loopback only. The rest of the
definition is standard q35 boilerplate (PCI root ports, USB controller, serial console, virtio
serial channel, inputs, video, rng, balloon).

The destroy-on-poweroff policy is retained in the final definition. A guest-initiated poweroff
therefore removes the domain instead of stopping it, which is intended for the install cleanup
but worth knowing during normal use.

## Running the install

1. Define the install-boot XML with `sudo virsh define`, or edit the existing definition to add
   the three `<os>` kernel lines and the two CDROM devices.
2. Start it with `sudo virsh start fedora-cinnamon-ref`.
3. Watch the serial console with `sudo virsh console fedora-cinnamon-ref`. The VNC console on
   5901 is bound to loopback, so reach it over the SSH tunnel in the Console access section.
4. Anaconda runs the kickstart unattended, pulls the package set from the mirror, and ends with
   `poweroff`. The recorded run installed 1531 packages. Because of `<on_poweroff>destroy`, the
   domain goes away on its own when the install finishes.

## Console access

Two consoles. The serial console (`sudo virsh console fedora-cinnamon-ref`) is text. It works
from the first boot, and it still works after the install, because the disk boot's kernel
command line carries `console=ttyS0,115200n8` (the Finalization section records the verified
disk boot). VNC 5901 is the graphical console.

The VNC console is bound to loopback only (`listen='127.0.0.1'` in the domain XML), so it is
not reachable from the network. Reach it over an SSH tunnel from the host LAN. The tunnel for
`fedora-cinnamon-ref` (VNC 5901) is

```
ssh -L 5901:127.0.0.1:5901 howard@192.168.1.102
```

then point a VNC client at `127.0.0.1:5901`. For the sibling `rocky10-explore` (VNC 5902), the
only change is the port, on both sides of `-L`.

```
ssh -L 5902:127.0.0.1:5902 howard@192.168.1.102
```

Do not bind VNC to `0.0.0.0` without a password. libvirt VNC has no password by default, so a
`0.0.0.0` bind is an unauthenticated network console reachable from anywhere that can route to
the host. That is why the domain binds to loopback and the console is reached over the tunnel.

## Finalization. The repair-boot trap

During the install, a root shell was reached on the console by adding a repair-boot element to
the domain XML. A `<kernel>/<initrd>/<cmdline>` triple pointing at the installed system's kernel
and initramfs (the files in `fc-inst/`, copied there for this repair), with the installed root
UUID and `init=/bin/bash` in the cmdline.

```xml
<kernel>/home/howard/ISOs/fc-inst/vmlinuz</kernel>
<initrd>/home/howard/ISOs/fc-inst/initramfs.img</initrd>
<cmdline>root=UUID=<installed-root-uuid> rw rootflags=subvol=root console=tty0,115200n8 console=ttyS0,115200n8 init=/bin/bash</cmdline>
```

**The trap.** If that triple is left in the persistent XML, every start of the domain drops into
a bare root shell instead of the installed GRUB. QEMU's `-kernel` flag bypasses firmware boot
order entirely, so the disk's boot order 1 is never consulted. The domain looks like it is
booting, and the console lands in bash with no init.

**Detection.**

```
sudo virsh dumpxml fedora-cinnamon-ref | grep -E '<kernel>|<initrd>|<cmdline>'
```

Any hit under `<os>` means the trap is armed. The runtime symptom is a bash root shell on the
console at boot, with no GRUB menu.

**Removal.**

1. `sudo virsh destroy fedora-cinnamon-ref`. The definition can only be changed while the domain
   is stopped.
2. `sudo virsh edit fedora-cinnamon-ref`, delete the three lines in `<os>`, save.
3. Remove the CDROM devices too. The final state has no CDROMs at all.
4. `sudo virsh start fedora-cinnamon-ref`.

A guest reboot does not apply the change, because the QEMU command line is fixed at process
start. The destroy-and-start cycle is required.

After removal, verify that the VM boots the installed GRUB, comes up on 192.168.122.x, and
answers `ssh howard@<ip>` with the host key. The serial console works on the disk boot. The
install ran with `console=ttyS0,115200n8` in the install-boot cmdline, and Anaconda carries that
console setting into the installed GRUB config. The verified disk boot (2026-09-01, from the
running VM) shows `console=tty0,115200n8 console=ttyS0,115200n8` in `/proc/cmdline` with no
`rhgb` and no `quiet`, so `sudo virsh console fedora-cinnamon-ref` shows the full GRUB menu and
boot output from the disk boot. VNC 5901 is the graphical console, reached over the SSH tunnel
in the Console access section.

## The installed result

Verified 2026-09-01 from the running VM.

| Item | Value |
|---|---|
| OS | Fedora 44. Kernel 7.1.10-200.fc44 from the installed /boot, via GRUB |
| Cinnamon | 6.6.7 (`cinnamon-6.6.7-7.fc44`, `cinnamon-session-6.6.4-1.fc44`, `nemo-6.6.3-3.fc44`) |
| Display manager | lightdm, enabled. The F44 Cinnamon spin ships lightdm, not gdm |
| Init | systemd running, no anaconda process |
| Disk | `/home/howard/vm-disks/fedora-cinnamon-ref.qcow2` (32G sparse) |
| Network | 192.168.122.156/24 on virbr0, via DHCP |
| Console | VNC 5901, bound to loopback only, reached over the SSH tunnel |

The reference runs the stock F44 Cinnamon 6.6.7, which predates the 6.7.x series built in this
repo. It is a reference for the complete desktop, not a version-matched baseline.

Access is SSH-key only. The root password is locked (`rootpw --lock`), so no root password
exists. `howard` is in `wheel` and authorized for the host's two public keys (comments
`sparky@team-chaotix-host` and `cinnamon-test`).

```
ssh howard@192.168.122.156
```
