Name:           gnome-terminal
Version:        3.54.5
Release:        1.el10
Summary:        The GNOME terminal emulator application

# Programme is GPL-3.0-or-later; the installed appstream metainfo is
# GFDL-1.3-only. Help (GPL-3.0-only + CC-BY-SA-3.0) is not built.
License:        GPLv3+ AND GFDL-1.3-only
URL:            https://www.gnome.org/software/terminal/
# Official GNOME source tarball:
# https://download.gnome.org/sources/gnome-terminal/3.54/gnome-terminal-3.54.5.tar.xz
Source0:        gnome-terminal-3.54.5.tar.xz
# sha256 (GNOME-published, gnome-terminal-3.54.5.sha256sum from the same
# directory, recorded 2026-09-17 with sha256sum):
# 132699f818341779c8aa9c0d049b778cbc6f82c1c37a17530354a47049962551

BuildRequires:  meson >= 0.62.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  pkgconf-pkg-config
BuildRequires:  glib2-devel >= 2.52.0
BuildRequires:  gtk3-devel >= 3.22.27
BuildRequires:  libhandy-devel >= 1.6.0
BuildRequires:  vte291-devel >= 0.78.0
BuildRequires:  pcre2-devel >= 10.0
BuildRequires:  libuuid-devel
BuildRequires:  libX11-devel
BuildRequires:  gsettings-desktop-schemas-devel >= 0.1.0
BuildRequires:  libxslt
BuildRequires:  gettext

Requires:       glib2 >= 2.52.0
Requires:       gtk3 >= 3.22.27
Requires:       libhandy >= 1.6.0
Requires:       vte291 >= 0.78.0
Requires:       pcre2
Requires:       libuuid
Requires:       libX11
Requires:       dbus
Requires:       gsettings-desktop-schemas

%description
GNOME Terminal is the terminal emulator of the GNOME desktop. The
gnome-terminal binary is a thin client that talks to a per-user
D-Bus-activated gnome-terminal-server process, which renders with
VTE 2.91 (GTK3, libhandy) and owns the actual PTYs. Source-built for
Rocky Linux 10 because no EL10 or EPEL repo carries gnome-terminal
(TASK-0017 item 1.4). Version 3.54.5 is the newest upstream release
whose VTE floor (0.78.0) EL10's vte291 0.78.6 satisfies; the Fedora 44
reference (3.60.0) requires vte291 >= 0.79.90, which EL10 does not
ship.

%prep
%setup -q

%build
# The Cinnamon file manager (nemo) uses the libnemo-extension API, not
# GNOME's libnautilus-extension, so the Nautilus "Open Terminal" tab
# integration is dead weight here and its build dependency is not in the
# EL10 repos.
# docs=false: help/ and man/ pull in gtk-doc, itstool and yelp-tools;
# the yelp help is not part of the TASK-0017 parity matrix.
# The upstream vte.wrap subproject is a fallback only; meson uses the
# system vte291-devel (0.78.6 >= 0.78.0).
# libdir=%{_libdir} so the gschemas.compiled pkglibdir lands in
# /usr/lib64/gnome-terminal on EL10.
# Explicit meson/ninja commands (python3-xapp.spec house pattern): the
# EL10 meson setup macro builds into redhat-linux-build/ but its ninja
# macro runs in the source directory, so the macro pair is inconsistent.
meson setup build \
    --wrap-mode=nodownload \
    -Dprefix=/usr \
    -Dlibdir=%{_libdir} \
    -Dnautilus_extension=false \
    -Ddocs=false
ninja -C build

%install
DESTDIR=%{buildroot} ninja -C build install
%find_lang %{name} --with-gnome

%files -f %{name}.lang
%license COPYING COPYING.GFDL
%doc README.md
%{_bindir}/gnome-terminal
%{_libexecdir}/gnome-terminal-server
%{_libexecdir}/gnome-terminal-preferences
# Upstream hardcodes the user unit to prefix/lib/systemd/user (not
# libdir), so it lands in /usr/lib/systemd/user. EL10's unitdir macro
# points at /usr/lib/systemd/system, so it cannot be used for user
# units; the explicit path mirrors the upstream install rule.
%{_prefix}/lib/systemd/user/gnome-terminal-server.service
%{_libdir}/gnome-terminal/gschemas.compiled
%{_datadir}/applications/org.gnome.Terminal.desktop
%{_datadir}/applications/org.gnome.Terminal.Preferences.desktop
%{_datadir}/xdg-terminals/org.gnome.Terminal.desktop
%{_datadir}/dbus-1/services/org.gnome.Terminal.service
%{_datadir}/glib-2.0/schemas/org.gnome.Terminal.gschema.xml
%{_datadir}/gnome-shell/search-providers/gnome-terminal-search-provider.ini
%{_datadir}/icons/hicolor/scalable/apps/org.gnome.Terminal.svg
%{_datadir}/icons/hicolor/scalable/apps/org.gnome.Terminal.Preferences.svg
%{_datadir}/icons/hicolor/symbolic/apps/org.gnome.Terminal-symbolic.svg
%{_datadir}/icons/hicolor/symbolic/apps/org.gnome.Terminal.Preferences-symbolic.svg
%{_datadir}/metainfo/org.gnome.Terminal.metainfo.xml
%{_datadir}/metainfo/org.gnome.Terminal.Nautilus.metainfo.xml

%changelog
* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 3.54.5-1.el10
- Initial port to Rocky Linux 10 (TASK-0017 item 1.4)
- 3.54.5 is the newest release whose vte-2.91 floor (0.78.0) EL10's
  vte291 0.78.6 satisfies (the Fedora 44 reference 3.60.0 needs >= 0.79.90)
- Nautilus extension disabled (nemo uses the libnemo-extension API;
  libnautilus-extension is not in the EL10 repos)
- Help and man pages disabled (not part of the parity matrix)
