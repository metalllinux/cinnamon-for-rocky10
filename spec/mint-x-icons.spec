# mint-x-icons: the Linux Mint Mint-X icon themes (12 themes), as shipped by
# Linux Mint 22.3 (zena).
#
# Provenance:
# - Source0 is the zena .deb itself (packages.linuxmint.com shared pool), the
#   byte source of what the LM 22.3 reference system ships under
#   /usr/share/icons/Mint-X*/; the .deb SHA256 matches the zena Packages
#   index entry recorded below (TASK-0038 window-button theme
#   availability, 2026-11-02).
# - Upstream: https://github.com/linuxmint/mint-x-icons (per the package
#   copyright file, Upstream-Name: mint-x-icons), tag 1.7.5.
# - License: GPL-3+ per the package copyright file ("Files: *"), shipped in
#   the package.
#
# Payload: 12 icon themes under /usr/share/icons (Mint-X and 11 colour
# variants including Yellow), each a full icon theme with index.theme
# (Directories=), plus the folder-color-switcher colour map for nemo.

Name:           mint-x-icons
Version:        1.7.5
Release:        1.el10
Summary:        Mint-X icon themes for Cinnamon on Rocky 10
License:        GPL-3.0-or-later
URL:            https://github.com/linuxmint/mint-x-icons
Source0:        http://packages.linuxmint.com/pool/main/m/mint-x-icons/mint-x-icons_1.7.5_all.deb
# SHA256: 217b54fb4a28630cf655799e2c95b1dfd6f4536c4977ca70724fd0b703f4e08e
# (packages.linuxmint.com zena Packages index, verified at download)

BuildArch:      noarch
Requires:       hicolor-icon-theme

%description
The Mint-X icon themes as shipped by Linux Mint 22.3: 12 full icon themes
(Mint-X plus 11 colour variants including Yellow), each with its
index.theme (Directories=) so the Cinnamon Themes panel accepts them as
the icon part of the Mint-X style, plus the folder-color-switcher colour
map. The 11 non-Yellow themes pair with the Mint-X gtk themes of
mint-themes (TASK-0038 window-button theme availability).

%prep
# Source0 is a .deb (ar archive), not an RPM or tarball: split the archive
# and extract the payload tree.
rm -rf mint-x-icons
mkdir -p mint-x-icons
(
  cd mint-x-icons
  ar x %{SOURCE0}
  tar xf data.tar.xz
)

%install
# The payload tree, byte-identical to the zena data.tar: 12 icon themes
# plus the folder-color-switcher colour map.
cp -a mint-x-icons/usr %{buildroot}/
# Upstream copyright file (GPL-3+), relocated to the Rocky license path.
install -d %{buildroot}%{_datadir}/licenses/%{name}
mv %{buildroot}%{_datadir}/doc/%{name}/copyright \
    %{buildroot}%{_datadir}/licenses/%{name}/copyright

%files
%license %{_datadir}/licenses/%{name}/copyright
%doc %{_datadir}/doc/%{name}/changelog.gz
%{_datadir}/icons/Mint-X*/
%{_datadir}/folder-color-switcher/

%changelog
* Mon Nov 02 2026 Team Chaotix <chaotix@metallinux.dev> - 1.7.5-1.el10
- Initial package: full zena 1.7.5 payload (12 Mint-X* icon themes plus the
  folder-color-switcher colour map, bytes extracted from the LM 22.3 .deb,
  provenance in the spec header) so the Mint-X style resolves its icon part
  in the Cinnamon Themes panel (TASK-0038 window-button theme
  availability).
