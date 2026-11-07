# mint-themes: the Linux Mint Mint-X and Mint-Y gtk/cinnamon theme families,
# as shipped by Linux Mint 22.3 (zena).
#
# Provenance:
# - Source0 is the zena .deb itself (packages.linuxmint.com shared pool),
#   the byte source of what the LM 22.3 reference system ships under
#   /usr/share/themes/Mint-{X,Y}*/; the .deb SHA256 matches the zena
#   Packages index entry recorded below (TASK-0038 window-button theme
#   availability, 2026-11-02).
# - Upstream: https://github.com/linuxmint/mint-themes (per the package
#   copyright file, Upstream-Name: mint-themes), tag 2.3.8.
# - License: GPL-3+ per the package copyright file ("Files: *"), shipped in
#   the package.
#
# Payload: 35 theme directories under /usr/share/themes: the Mint-X family
# (Mint-X plus 10 colour variants, and Mint-X-compact) and the Mint-Y
# family (Mint-Y plus 10 colour variants, and the Mint-Y-Dark family, 22
# total). Every non-compact theme carries gtk-2.0/, gtk-3.0/ (gtk.css),
# the cinnamon/ shell theme, index.theme, and WM assets. There is no
# Mint-X-Dark family upstream, and the repo ships no styles.d file, so the
# Mint-X styles file is project-authored (see
# spec/cinnamon-rocky-defaults.spec, 10_mint-x.styles).

Name:           mint-themes
Version:        2.3.8
Release:        1.el10
Summary:        Mint-X and Mint-Y gtk/cinnamon theme families for Cinnamon on Rocky 10
License:        GPL-3.0-or-later
URL:            https://github.com/linuxmint/mint-themes
Source0:        http://packages.linuxmint.com/pool/main/m/mint-themes/mint-themes_2.3.8_all.deb
# SHA256: 7c5b71f855ec0bda74c3fa86be40a1e4d897dada1a057e3654773e38e47c93fe
# (packages.linuxmint.com zena Packages index, verified at download)

BuildArch:      noarch
Requires:       mint-x-icons
Requires:       mint-y-icons

%description
The Mint-X and Mint-Y gtk/cinnamon theme families as shipped by Linux Mint
22.3: the 12 Mint-X* theme directories (Mint-X plus 10 colour variants and
Mint-X-compact) and the 22 Mint-Y* theme directories (Mint-Y plus 10 colour
variants, plus the Mint-Y-Dark family), each with gtk-2.0, gtk-3.0,
cinnamon shell, metacity, openbox, xfwm4, and libadwaita assets where
upstream ships them. The Mint-X family provides the gtk-3.0 themes that
carry the Mint-X window-button styles in the Cinnamon Themes panel
(TASK-0038 window-button theme availability); the icon themes come from
mint-x-icons and mint-y-icons (upstream dependencies, mirrored). The
Mint-Y family rides along as part of the same upstream package, matching
the F45 Cinnamon baseline's mint-themes payload.

%prep
# Source0 is a .deb (ar archive), not an RPM or tarball: split the archive
# and extract the payload tree.
rm -rf mint-themes
mkdir -p mint-themes
(
  cd mint-themes
  ar x %{SOURCE0}
  tar xf data.tar.xz
)

%install
# The payload tree, byte-identical to the zena data.tar: 35 theme
# directories.
cp -a mint-themes/usr %{buildroot}/
# Upstream copyright file (GPL-3+), relocated to the Rocky license path.
install -d %{buildroot}%{_datadir}/licenses/%{name}
mv %{buildroot}%{_datadir}/doc/%{name}/copyright \
    %{buildroot}%{_datadir}/licenses/%{name}/copyright

%files
%license %{_datadir}/licenses/%{name}/copyright
%doc %{_datadir}/doc/%{name}/changelog.gz
%{_datadir}/themes/Mint-X*/
%{_datadir}/themes/Mint-Y*/

%changelog
* Mon Nov 02 2026 Team Chaotix <chaotix@metallinux.dev> - 2.3.8-1.el10
- Initial package: full zena 2.3.8 payload (12 Mint-X* plus 22 Mint-Y*
  theme directories, bytes extracted from the LM 22.3 .deb, provenance in
  the spec header) so the Mint-X window-button themes are selectable in
  the Cinnamon Themes panel (TASK-0038 window-button theme availability).
