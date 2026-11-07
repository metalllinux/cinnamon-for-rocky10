# mint-l-icons: the Linux Mint Mint-L icon themes (12 themes), as shipped by
# Linux Mint 22.3 (zena).
#
# Provenance:
# - Source0 is the zena .deb itself (packages.linuxmint.com shared pool), the
#   byte source of what the LM 22.3 reference system ships under
#   /usr/share/icons/Mint-L*/; the .deb SHA256 matches the zena Packages
#   index entry recorded below (TASK-0038 window-button theme
#   availability, 2026-11-02).
# - Upstream: https://github.com/linuxmint/mint-l-icons (per the package
#   copyright file, Upstream-Name: mint-l-icons); zena carries 1.8.0, which
#   is ahead of the newest upstream tag (1.7.1), so the zena .deb is the
#   ref actually used.
# - License: per the package copyright file, "Files: *" is GPL-3+ while
#   "Files: usr/share/icons/*" is CC-BY-SA-4 (Sam Hewitt, Alexey
#   Varfolomeev, 2015); the copyright file ships in the package.
#
# Payload: 12 icon themes under /usr/share/icons (Mint-L and 11 colour
# variants including Yellow), each a full icon theme with index.theme
# (Directories=), plus the folder-color-switcher colour map for nemo.

Name:           mint-l-icons
Version:        1.8.0
Release:        1.el10
Summary:        Mint-L icon themes for Cinnamon on Rocky 10
License:        CC-BY-SA-4.0 AND GPL-3.0-or-later
URL:            https://github.com/linuxmint/mint-l-icons
Source0:        http://packages.linuxmint.com/pool/main/m/mint-l-icons/mint-l-icons_1.8.0_all.deb
# SHA256: d8cce225edd433af85d9c410455b690b0659c178e278126fc7772c8ea3f0b40d
# (packages.linuxmint.com zena Packages index, verified at download)

BuildArch:      noarch
Requires:       hicolor-icon-theme

%description
The Mint-L icon themes as shipped by Linux Mint 22.3: 12 full icon themes
(Mint-L plus 11 colour variants including Yellow), each with its
index.theme (Directories=) so the Cinnamon Themes panel accepts them as
the icon part of the Mint-L and Mint-X styles, plus the
folder-color-switcher colour map. The 11 non-Yellow themes pair with the
Mint-L gtk themes of mint-l-theme (TASK-0038 window-button theme
availability); the icon art is CC-BY-SA-4.0 (Sam Hewitt, Alexey
Varfolomeev) per the shipped copyright file.

%prep
# Source0 is a .deb (ar archive), not an RPM or tarball: split the archive
# and extract the payload tree.
rm -rf mint-l-icons
mkdir -p mint-l-icons
(
  cd mint-l-icons
  ar x %{SOURCE0}
  tar xf data.tar.xz
)

%install
# The payload tree, byte-identical to the zena data.tar: 12 icon themes
# plus the folder-color-switcher colour map.
cp -a mint-l-icons/usr %{buildroot}/
# Upstream copyright file (GPL-3+ / CC-BY-SA-4.0 per file class), relocated
# to the Rocky license path.
install -d %{buildroot}%{_datadir}/licenses/%{name}
mv %{buildroot}%{_datadir}/doc/%{name}/copyright \
    %{buildroot}%{_datadir}/licenses/%{name}/copyright

%files
%license %{_datadir}/licenses/%{name}/copyright
%doc %{_datadir}/doc/%{name}/changelog.gz
%{_datadir}/icons/Mint-L*/
%{_datadir}/folder-color-switcher/

%changelog
* Mon Nov 02 2026 Team Chaotix <chaotix@metallinux.dev> - 1.8.0-1.el10
- Initial package: full zena 1.8.0 payload (12 Mint-L* icon themes plus the
  folder-color-switcher colour map, bytes extracted from the LM 22.3 .deb,
  provenance in the spec header) so the Mint-L styles resolve their icon
  part in the Cinnamon Themes panel (TASK-0038 window-button theme
  availability).
