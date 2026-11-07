# mint-y-icons: the Linux Mint icon themes (Mint-Y and variants), as built
# for Fedora 45. This package ships a curated subset, not the full theme.
#
# Provenance:
# - Source0 is the F45 noarch RPM itself (kojipkgs), the byte source of
#   what the F45 Cinnamon baseline VM (181) has installed under
#   /usr/share/icons/{Mint-Y,Mint-Y-Aqua}/; the extracted subset is
#   verified byte-identical against 181 (TASK-0038 icon parity,
#   2026-11-01).
# - Upstream: https://github.com/linuxmint/mint-y-icons (per the package
#   copyright file, Upstream-Name: mint-y-icons).
# - License: the shipped icons/ subtree is CC-BY-SA-4.0 (Sam Hewitt,
#   Alexey Varfolomeev, 2015) per the copyright file's
#   "Files: usr/share/icons/*" section; the package-level declaration is
#   kept as upstream (CC-BY-SA-4.0 AND GPL-3.0-or-later). The upstream
#   copyright file ships in the package.

Name:           mint-y-icons
Version:        1.9.2
Release:        1.el10
Summary:        Mint-Y icon themes, curated subset for Cinnamon on Rocky 10
License:        CC-BY-SA-4.0 AND GPL-3.0-or-later
URL:            https://github.com/linuxmint/mint-y-icons
Source0:        http://kojipkgs.fedoraproject.org/packages/mint-y-icons/1.9.2/1.fc45/noarch/%{name}-%{version}-1.fc45.noarch.rpm
# SHA256: 02c32fc5bfd4f67c3bead4af5c2f77e67af8ac23d612c18f5818fa921dd99d05

BuildArch:      noarch
Requires:       hicolor-icon-theme

%description
Curated subset of the Mint-Y icon themes as shipped by Fedora's
mint-y-icons 1.9.2-1.fc45: the full Mint-Y-Aqua theme (places icons:
nemo, user-home, user-trash, user-trash-full, user-desktop, and the rest
of the places set), the Mint-Y app icons org.gnome.Terminal and firefox,
the Mint-Y category icon preferences-desktop, the two theme index files,
and the upstream copyright file. This is exactly what the Cinnamon
desktop renders for the F45 baseline's taskbar (task menu) and desktop
icons: on the baseline the active icon theme is Mint-Y-Aqua, and the
nemo, terminal, firefox, and System Settings window icons resolve in the
Mint-Y/Mint-Y-Aqua chain. The cinnamon-rocky-defaults package sets
icon-theme='Mint-Y-Aqua' and Requires this package, so a fresh consumer
renders the same icon art as the baseline (TASK-0038 icon parity).

%prep
# Source0 is an RPM, not a tarball: extract its payload tree.
rm -rf mint-y
mkdir -p mint-y
(
  cd mint-y
  rpm2cpio %{SOURCE0} | cpio -idm --quiet
)

%install
# Theme index files, byte-identical to the F45 payload.
install -d %{buildroot}%{_datadir}/icons/Mint-Y
install -d %{buildroot}%{_datadir}/icons/Mint-Y-Aqua
install -m 0644 mint-y/usr/share/icons/Mint-Y/index.theme \
    %{buildroot}%{_datadir}/icons/Mint-Y/
install -m 0644 mint-y/usr/share/icons/Mint-Y-Aqua/index.theme \
    %{buildroot}%{_datadir}/icons/Mint-Y-Aqua/
# The in-scope Mint-Y icon names plus their symlink targets. The F45
# payload is a symlink farm: org.gnome.Terminal.png is a relative link
# to utilities-terminal.png, preferences-desktop.png is an absolute link
# to /usr/share/icons/Mint-Y/apps/<size>/yast.png (both in this
# package), firefox.png is a regular file. Ship the leaves and their
# targets with cp -a so the link structure is preserved byte-identically;
# all 16 fixed-size dirs (8 sizes plus @2x).
for d in 16 16@2x 22 22@2x 24 24@2x 32 32@2x 48 48@2x 64 64@2x 96 96@2x 256 256@2x; do
    install -d %{buildroot}%{_datadir}/icons/Mint-Y/apps/$d
    install -d %{buildroot}%{_datadir}/icons/Mint-Y/categories/$d
    cp -a mint-y/usr/share/icons/Mint-Y/apps/$d/org.gnome.Terminal.png \
        %{buildroot}%{_datadir}/icons/Mint-Y/apps/$d/
    cp -a mint-y/usr/share/icons/Mint-Y/apps/$d/utilities-terminal.png \
        %{buildroot}%{_datadir}/icons/Mint-Y/apps/$d/
    cp -a mint-y/usr/share/icons/Mint-Y/apps/$d/firefox.png \
        %{buildroot}%{_datadir}/icons/Mint-Y/apps/$d/
    cp -a mint-y/usr/share/icons/Mint-Y/apps/$d/yast.png \
        %{buildroot}%{_datadir}/icons/Mint-Y/apps/$d/
    cp -a mint-y/usr/share/icons/Mint-Y/categories/$d/preferences-desktop.png \
        %{buildroot}%{_datadir}/icons/Mint-Y/categories/$d/
done
# Full Mint-Y-Aqua: the upstream payload is places/ only (288 regular
# png plus 464 same-directory alias symlinks, verified no escapes), plus
# index.theme; cp -a preserves the links.
cp -a mint-y/usr/share/icons/Mint-Y-Aqua/places \
    %{buildroot}%{_datadir}/icons/Mint-Y-Aqua/
# Upstream copyright file (CC-BY-SA-4.0 attribution for the icons).
install -d %{buildroot}%{_datadir}/licenses/mint-y-icons
install -m 0644 mint-y/usr/share/licenses/mint-y-icons/copyright \
    %{buildroot}%{_datadir}/licenses/mint-y-icons/

%files
%license %{_datadir}/licenses/mint-y-icons/copyright
%dir %{_datadir}/icons/Mint-Y
%{_datadir}/icons/Mint-Y/index.theme
%{_datadir}/icons/Mint-Y/apps/
%{_datadir}/icons/Mint-Y/categories/
%{_datadir}/icons/Mint-Y-Aqua/

%changelog
* Sat Nov 01 2026 Team Chaotix <chaotix@metallinux.dev> - 1.9.2-1.el10
- Initial package: curated subset of mint-y-icons 1.9.2-1.fc45 (bytes
  extracted from the F45 noarch RPM, provenance in the spec header).
  Full Mint-Y-Aqua theme (including its 464 alias symlinks), Mint-Y
  apps/{org.gnome.Terminal,firefox}.png and categories/preferences-desktop.png
  at 16 fixed sizes including @2x together with their symlink target files
  (utilities-terminal.png, yast.png), both theme index files, upstream
  copyright file (TASK-0038 icon parity).
