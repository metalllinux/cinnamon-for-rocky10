# mint-cursor-themes: the Linux Mint cursor themes (8 cursor icon themes),
# as shipped by Linux Mint 22.3 (zena).
#
# Provenance:
# - Source0 is the zena .deb itself (packages.linuxmint.com shared pool),
#   the byte source of what the LM 22.3 reference system ships under
#   /usr/share/icons/{Bibata-*,GoogleDot-*,XCursor-Pro-*/; the .deb
#   SHA256 matches the zena Packages index entry recorded below
#   (TASK-0038 window-button theme availability, 2026-11-02).
# - Upstream: https://github.com/linuxmint/mint-cursor-themes (per the
#   package copyright file, Upstream-Name: mint-cursor-themes); the repo
#   has no version tag, zena carries 1.0.2, so the zena .deb is the ref
#   actually used.
# - License: GPL-3+ per the package copyright file ("Files: *"), shipped in
#   the package.
#
# Payload: 8 cursor icon themes under /usr/share/icons (Bibata-Modern-
# Classic, Bibata-Modern-Ice, Bibata-Original-Classic, Bibata-Original-
# Ice, GoogleDot-Black, GoogleDot-White, XCursor-Pro-Dark,
# XCursor-Pro-Light), each with a cursors/ directory, so the Cinnamon
# Themes panel accepts them as the cursor part of a style. Bibata-Modern-
# Classic is the cursor named by 00_mint-l.styles (mint-l-theme) and by
# the project-authored 10_mint-x.styles (cinnamon-rocky-defaults).

Name:           mint-cursor-themes
Version:        1.0.2
Release:        1.el10
Summary:        Linux Mint cursor themes for Cinnamon on Rocky 10
License:        GPL-3.0-or-later
URL:            https://github.com/linuxmint/mint-cursor-themes
Source0:        http://packages.linuxmint.com/pool/main/m/mint-cursor-themes/mint-cursor-themes_1.0.2_all.deb
# SHA256: a0058085cdf5bcedf9698c91efa82a36179b95ef83af2a64b67639a5066cf020
# (packages.linuxmint.com zena Packages index, verified at download)

BuildArch:      noarch
Requires:       hicolor-icon-theme

%description
The Linux Mint cursor themes as shipped by Linux Mint 22.3: 8 cursor icon
themes (the Bibata modern/original classic and ice sets, GoogleDot black
and white, and XCursor-Pro dark and light), each an icon theme with a
cursors/ directory. Bibata-Modern-Classic is the cursor theme named by
the Mint-L styles file (00_mint-l.styles in mint-l-theme) and by the
Mint-X styles file (10_mint-x.styles in cinnamon-rocky-defaults), so the
Mint-L and Mint-X styles resolve their cursor part in the Cinnamon Themes
panel (TASK-0038 window-button theme availability).

%prep
# Source0 is a .deb (ar archive), not an RPM or tarball: split the archive
# and extract the payload tree.
rm -rf mint-cursor-themes
mkdir -p mint-cursor-themes
(
  cd mint-cursor-themes
  ar x %{SOURCE0}
  tar xf data.tar.xz
)

%install
# The payload tree, byte-identical to the zena data.tar: 8 cursor icon
# themes.
cp -a mint-cursor-themes/usr %{buildroot}/
# Upstream copyright file (GPL-3+), relocated to the Rocky license path.
install -d %{buildroot}%{_datadir}/licenses/%{name}
mv %{buildroot}%{_datadir}/doc/%{name}/copyright \
    %{buildroot}%{_datadir}/licenses/%{name}/copyright

%files
%license %{_datadir}/licenses/%{name}/copyright
%doc %{_datadir}/doc/%{name}/changelog.gz
%{_datadir}/icons/Bibata-Modern-Classic/
%{_datadir}/icons/Bibata-Modern-Ice/
%{_datadir}/icons/Bibata-Original-Classic/
%{_datadir}/icons/Bibata-Original-Ice/
%{_datadir}/icons/GoogleDot-Black/
%{_datadir}/icons/GoogleDot-White/
%{_datadir}/icons/XCursor-Pro-Dark/
%{_datadir}/icons/XCursor-Pro-Light/

%changelog
* Mon Nov 02 2026 Team Chaotix <chaotix@metallinux.dev> - 1.0.2-1.el10
- Initial package: full zena 1.0.2 payload (8 cursor icon themes, bytes
  extracted from the LM 22.3 .deb, provenance in the spec header) so the
  Bibata-Modern-Classic cursor named by the Mint-L and Mint-X styles
  resolves in the Cinnamon Themes panel (TASK-0038 window-button theme
  availability).
