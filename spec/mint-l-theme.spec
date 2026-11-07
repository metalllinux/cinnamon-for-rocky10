# mint-l-theme: the Linux Mint Mint-L theme family (gtk-2/gtk-3/cinnamon shell
# themes, window-manager assets) plus the upstream 00_mint-l.styles file that
# makes the family selectable in the Cinnamon Themes panel, as shipped by
# Linux Mint 22.3 (zena).
#
# Provenance:
# - Source0 is the zena .deb itself (packages.linuxmint.com shared pool), the
#   byte source of what the LM 22.3 reference system (operator input
#   screenshots/lm-22-3/2026-11-02/wanted_themes.png) ships for the Mint-L
#   family; the .deb SHA256 matches the zena Packages index entry recorded
#   below (TASK-0038 window-button theme availability, 2026-11-02).
# - Upstream: https://github.com/linuxmint/mint-l-theme (per the package
#   copyright file, Upstream-Name: mint-l-theme), tag 2.0.6.
# - License: GPL-3+ per the package copyright file ("Files: *"), shipped in
#   the package.
#
# Payload: 33 theme directories under /usr/share/themes (Mint-L and 10 colour
# variants, plus the -Dark and -Darker subfamilies, 11 each), each with
# gtk-2.0/, gtk-3.0/ (gtk.css), libadwaita, metacity-1, and xfwm4 assets.
# The cinnamon/ shell theme is upstream for the 22 base+-Dark themes; the
# 11 -Darker themes have no cinnamon style upstream (their index.theme
# pairs each -Darker gtk theme with the matching -Dark metacity theme,
# MetacityTheme=Mint-L-Dark), so this package adds a project-derived
# cinnamon/ for each -Darker theme, a byte copy of the matching -Dark
# theme's cinnamon/ directory, which is the window-button (Cinnamon shell)
# theme the -Darker family is designed to take. That makes all 33 Mint-L
# themes appear in the Cinnamon window-button selector (the "Desktop"
# chooser lists a theme iff its directory contains a cinnamon/
# subdirectory), matching the operator reference (wanted_themes.png).
# Also /usr/share/cinnamon/styles.d/00_mint-l.styles (mixed/dark/light,
# 11 variants each, cursor Bibata-Modern-Classic).

Name:           mint-l-theme
Version:        2.0.6
Release:        2.el10
Summary:        Mint-L theme family for Cinnamon on Rocky 10
License:        GPL-3.0-or-later
URL:            https://github.com/linuxmint/mint-l-theme
Source0:        http://packages.linuxmint.com/pool/main/m/mint-l-theme/mint-l-theme_2.0.6_all.deb
# SHA256: 364ed739b71eb47ed7e445e83b12ef7d7e063509a3b83fda53d297ddb792f569
# (packages.linuxmint.com zena Packages index, verified at download)

BuildArch:      noarch
Requires:       mint-l-icons

%description
The Mint-L theme family as shipped by Linux Mint 22.3: 33 gtk-3.0 themes
(Mint-L plus 10 colour variants, and the -Dark and -Darker subfamilies,
11 each) with gtk-2.0, cinnamon shell, metacity, xfwm4, and libadwaita
assets, plus the upstream 00_mint-l.styles file. The styles file defines
the "Mint-L" style with mixed/dark/light sections of 11 colour variants
each (blue, aqua, teal, green, sand, brown, grey, orange, red, pink,
purple), every variant naming its Mint-L gtk theme, the matching Mint-L
icon theme, and the Bibata-Modern-Classic cursor. Together with
mint-l-icons, mint-themes, and mint-cursor-themes this makes every
Mint-L window-button theme selectable in the Cinnamon Themes panel
(TASK-0038 window-button theme availability). The icon themes come from
mint-l-icons (upstream dependency, mirrored).

%prep
# Source0 is a .deb (ar archive), not an RPM or tarball: split the archive
# and extract the payload tree.
rm -rf mint-l-theme
mkdir -p mint-l-theme
(
  cd mint-l-theme
  ar x %{SOURCE0}
  tar xf data.tar.xz
)

%install
# The payload tree, byte-identical to the zena data.tar: 33 theme
# directories, the styles.d file, the doc/ metadata.
cp -a mint-l-theme/usr %{buildroot}/
# Upstream copyright file (GPL-3+), relocated to the Rocky license path.
install -d %{buildroot}%{_datadir}/licenses/%{name}
mv %{buildroot}%{_datadir}/doc/%{name}/copyright \
    %{buildroot}%{_datadir}/licenses/%{name}/copyright

# Project derivation (not in the zena data.tar): the 11 -Darker themes
# have no upstream cinnamon/ shell theme, so they are missing from the
# Cinnamon window-button selector, which lists a theme only if its
# directory contains a cinnamon/ subdirectory. Each -Darker index.theme
# pairs the -Darker gtk theme with the matching -Dark metacity theme
# (MetacityTheme=Mint-L-Dark), so the matching -Dark theme's cinnamon/
# directory is the window-button theme the -Darker family takes. Copy it
# (byte copy, all 37 files) so all 33 Mint-L themes are selectable.
cp -a %{buildroot}%{_datadir}/themes/Mint-L-Dark/cinnamon \
    %{buildroot}%{_datadir}/themes/Mint-L-Darker/cinnamon
for suffix in Aqua Blue Brown Grey Orange Pink Purple Red Sand Teal
do
    cp -a %{buildroot}%{_datadir}/themes/Mint-L-Dark-${suffix}/cinnamon \
        %{buildroot}%{_datadir}/themes/Mint-L-Darker-${suffix}/cinnamon
done

%files
%license %{_datadir}/licenses/%{name}/copyright
%doc %{_datadir}/doc/%{name}/changelog.gz
%{_datadir}/themes/Mint-L*/
%{_datadir}/cinnamon/styles.d/00_mint-l.styles

%changelog
* Thu Nov 05 2026 Team Chaotix <chaotix@metallinux.dev> - 2.0.6-2.el10
- Add a project-derived cinnamon/ shell theme to each of the 11 -Darker
  themes (byte copy of the matching -Dark theme's cinnamon/ directory;
  the upstream -Darker meta theme pairs the -Darker gtk theme with the
  -Dark metacity theme, so the -Dark shell assets are the window-button
  theme of the -Darker family). Upstream ships no cinnamon/ for the
  -Darker themes, and the Cinnamon window-button selector lists a theme
  only if its directory contains a cinnamon/ subdirectory, so the
  1.0-1 payload left the Mint-L family short of 11 entries in the
  selector (22/11/20 vs the reference 33/11/20). TASK-0038
  window-button theme availability FAIL.

* Mon Nov 02 2026 Team Chaotix <chaotix@metallinux.dev> - 2.0.6-1.el10
- Initial package: full zena 2.0.6 payload (33 theme directories plus
  00_mint-l.styles, bytes extracted from the LM 22.3 .deb, provenance in
  the spec header) so the Mint-L window-button themes are selectable in
  the Cinnamon Themes panel (TASK-0038 window-button theme availability).
