# xapp-symbolic-icons: standalone icon project in the xapp-project GitHub
# org; the source of the xsi-* symbolic icons the Cinnamon tray applets
# render.
#
# Provenance:
# - Upstream: https://github.com/xapp-project/xapp-symbolic-icons, tag
#   1.1.0 (Source0 tarball pinned below). NOT linuxmint/xapps: that repo's
#   master tree contains 0 xsi- files (verified 2026-11-01), and the F45
#   xapps 3.3.4 main package ships 40 generic-named icons, none xsi-.
# - Cross-reference: F45 SRPM xapp-symbolic-icons-1.1.0-2.fc45.src.rpm
#   (sha256 1fc4100e62a17cff9a77ac2b3e047dfaf42626f7bccef991c582734df32f7097,
#   kojipkgs) embeds a byte-identical tag tarball, and its 666 installed
#   svg names on the F45 baseline VM match the tag's 666 svg names
#   (sorted-basename diff empty) (TASK-0038 icon parity, 2026-11-01).

Name:           xapp-symbolic-icons
Version:        1.1.0
Release:        2.el10
Summary:        Symbolic icons for Cinnamon tray applets (xsi-* set)
License:        CC0-1.0 AND CC-BY-4.0 AND CC-BY-SA-4.0 AND GPL-3.0-only AND LGPL-3.0-only AND MIT AND BSD-3-Clause
URL:            https://github.com/xapp-project/xapp-symbolic-icons
Source0:        %{url}/archive/%{version}/%{name}-%{version}.tar.gz
# SHA256: fa96ac6a1a85c0cb16dccab5c03ae1e651a3482cde4a93f792956977bc19108d

BuildArch:      noarch
BuildRequires:  meson
Requires:       hicolor-icon-theme

%description
A set of symbolic icons which replaces the GNOME-specific Adwaita set.
All provided icons are prefixed with xsi-.
Icon names loosely follow the Adwaita names.
Shipped in the Cinnamon for Rocky 10 repo because the Cinnamon tray
applets (systray, xapp-status, notifications, printers, removable-drives,
network, nightlight, power, calendar, sound) set their icons via
set_applet_icon_symbolic_name('xsi-...'); without this set the
right-side panel cluster renders empty (TASK-0038 icon parity).

%prep
%autosetup

%build
meson setup builddir \
    --prefix=%{_prefix} \
    --buildtype=plain
ninja -C builddir -j2

%install
DESTDIR=%{buildroot} ninja -C builddir install

# hicolor changed: rebuild its cache (mirrors the upstream/Fedora spec).
%transfiletriggerin -- %{_datadir}/icons/hicolor
gtk-update-icon-cache --force %{_datadir}/icons/hicolor &>/dev/null || :

%transfiletriggerpostun -- %{_datadir}/icons/hicolor
gtk-update-icon-cache --force %{_datadir}/icons/hicolor &>/dev/null || :

%files
%license LICENSE LICENSES/*.txt
%doc AUTHORS README.md
%{_bindir}/xsi-replace-adwaita-symbolic
%{_datadir}/icons/hicolor/scalable/actions/xsi-*.svg
%{_datadir}/xapp/

%changelog
* Sat Nov 07 2026 Team Chaotix <chaotix@metallinux.dev> - 1.1.0-2.el10
- The License field now names every license family of the shipped text
  (adds GPL-3.0-only, BSD-3-Clause, and CC-BY-4.0); the text already
  ships via %%license, so this is metadata only, no payload change.
* Sat Nov 01 2026 Team Chaotix <chaotix@metallinux.dev> - 1.1.0-1.el10
- Initial package for the Cinnamon for Rocky 10 repo. Upstream tag 1.1.0
  (tarball byte-identical to the one embedded in the F45 SRPM 1.1.0-2).
  Provides the xsi-* symbolic set the Cinnamon tray applets render
  (TASK-0038 icon parity). The F45 package's changelog is a mass-rebuild
  (1.1.0-2) of 1.1.0-1 with no content change; not carried over.
