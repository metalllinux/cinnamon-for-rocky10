Name:           cinnamon
Version:        6.7.4
Release:        4.el10
Summary:        GNOME desktop environment fork providing the Cinnamon experience

License:        GPLv2+
URL:            https://github.com/linuxmint/cinnamon
Source0:        %{name}-%{version}.tar.gz
Patch0:         xdo-optional-gcr-4.patch

BuildRequires:  meson >= 0.64.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconf-pkg-config
BuildRequires:  cjs-devel >= 6.4.0
BuildRequires:  muffin-devel >= 5.2.0
BuildRequires:  muffin-clutter-devel >= 5.2.0
BuildRequires:  muffin-cogl-devel >= 5.2.0
BuildRequires:  cinnamon-menus-devel >= 4.8.0
BuildRequires:  gcr-devel >= 3.7.5
BuildRequires:  gtk3-devel >= 3.12
BuildRequires:  glib2-devel >= 2.79.2
BuildRequires:  polkit-devel >= 0.100
BuildRequires:  at-spi2-atk-devel
BuildRequires:  gobject-introspection-devel >= 0.9.2
BuildRequires:  libglvnd-devel
BuildRequires:  xapps-devel >= 2.6.0
BuildRequires:  libX11-devel
BuildRequires:  libXcomposite-devel
BuildRequires:  libXext-devel
BuildRequires:  libxml2-devel
BuildRequires:  NetworkManager-libnm-devel
BuildRequires:  libsecret-devel >= 0.18
BuildRequires:  gstreamer1-devel
BuildRequires:  gstreamer1-plugins-base-devel
BuildRequires:  pam-devel
BuildRequires:  sassc
BuildRequires:  dbus-devel
BuildRequires:  systemd-devel
BuildRequires:  python3-devel
BuildRequires:  gtk4-devel
BuildRequires:  gettext

# Runtime dependencies of the Python settings app (cinnamon-settings.py),
# which ships in this package. The app imports all six unguarded; the
# first four match the Requires of the Fedora cinnamon package (verified
# on the Fedora 44 reference).
Requires:       python3-setproctitle
Requires:       python3-pillow
Requires:       python3-tinycss2
# cinnamon-settings also imports xapp (bin/SettingsWidgets.py:10, xapp.os:33)
Requires:       python3-xapp
# The settings app imports requests and pexpect at module level,
# unguarded: harvester.py:16 (reached via cs_actions.py:7) and
# cs_user.py:10 (TASK-0038). Both are in EL10 baseos
# (python3-requests-2.32.4-1.el10_0, python3-pexpect-4.9.0-6.el10), so
# these Requires resolve without a new repository.
Requires:       python3-requests
Requires:       python3-pexpect

%description
Cinnamon is a desktop environment which provides advanced innovative
features on top of the traditional desktop metaphor. It is based on
the GNOME platform, but uses the Muffin window manager instead of
Mutter and CJS instead of GJS for the JavaScript runtime.

%prep
%setup -q

# Rocky 10 port adaptation: make libxdo optional (libxdo is not in the
# EL10 repositories) and adapt to the gcr-4 API (EL10 ships gcr 4.x, not
# 3.x). The patch is the complete adaptation the build needs, generated
# from the verified build state of the component checkout (the state the
# 6.7.4-4 build was made from, 2026-10-06, build host shadow); applying
# it to the pristine source reproduces that state byte for byte (all
# eight changed files cmp-identical, verified 2026-10-30).
%patch0 -p1

# Lower the cjs version requirement (upstream 6.4.0 vs Fedora 115.0).
# Not in the patch: the line is unchanged in the checkout, so it is fixed
# here, as the build always needed it.
sed -i "s/version: '>= 115.0'/version: '>= 6.4.0'/" meson.build

# Note: keeping version_compare('>= 139.9') as-is to avoid USE_GIR20 which
# needs gi_repository_dup_default() only in GLib >= 2.82.0 (we have 2.80.4)

%build
meson setup builddir \
    --prefix=%{_prefix} \
    --libdir=%{_libdir} \
    --buildtype=plain \
    -Dnm_agent=internal \
    -Dbuild_recorder=true \
    -Ddeprecated_warnings=false
ninja -C builddir -j2

%install
DESTDIR=%{buildroot} ninja -C builddir install

%files
%license COPYING
%{_bindir}/cinnamon
%{_bindir}/cinnamon2d
%{_bindir}/cinnamon-calendar-server
%{_bindir}/cinnamon-dbus-command
%{_bindir}/cinnamon-desktop-editor
%{_bindir}/cinnamon-file-dialog
%{_bindir}/cinnamon-hover-click
%{_bindir}/cinnamon-install-spice
%{_bindir}/cinnamon-json-makepot
%{_bindir}/cinnamon-keyboard-display
%{_bindir}/cinnamon-killer-daemon
%{_bindir}/cinnamon-launcher
%{_bindir}/cinnamon-looking-glass
%{_bindir}/cinnamon-menu-editor
%{_bindir}/cinnamon-preview-gtk-theme
%{_bindir}/cinnamon-screensaver-command
%{_bindir}/cinnamon-screenshot
%{_bindir}/cinnamon-session-cinnamon
%{_bindir}/cinnamon-settings
%{_bindir}/cinnamon-settings-users
%{_bindir}/cinnamon-slideshow
%{_bindir}/cinnamon-spice-updater
%{_bindir}/cinnamon-subprocess-wrapper
%{_bindir}/cinnamon-unlock-desktop
%{_bindir}/cinnamon-xlet-makepot
%{_bindir}/xlet-about-dialog
%{_bindir}/xlet-settings
%{_libexecdir}/cinnamon-*
%{_libdir}/cinnamon/
%{_datadir}/cinnamon/
%{_datadir}/cinnamon-session/sessions/cinnamon*.session
%{_datadir}/applications/cinnamon*.desktop
%{_datadir}/dbus-1/services/org.cinnamon.*
%{_datadir}/dbus-1/services/org.Cinnamon.*
%{_datadir}/desktop-directories/cinnamon-*.directory
%{_datadir}/glib-2.0/schemas/org.cinnamon*.gschema.xml
%{_datadir}/xsessions/cinnamon.desktop
%{_datadir}/wayland-sessions/cinnamon-wayland.desktop
%{_datadir}/polkit-1/actions/org.cinnamon*.policy
%{_mandir}/man1/cinnamon*.1*
%{_datadir}/icons/hicolor/scalable/apps/*cinnamon*
%{_datadir}/icons/hicolor/scalable/categories/cs-*
%{_datadir}/icons/hicolor/scalable/categories/*cinnamon*
%{_datadir}/icons/hicolor/scalable/devices/audio-speaker-*
%{_datadir}/icons/hicolor/scalable/devices/audio-subwoofer*
%{_datadir}/icons/hicolor/scalable/devices/bluetooth.svg
%{_datadir}/icons/hicolor/scalable/actions/*cinnamon*
%{_datadir}/icons/hicolor/scalable/emblems/cs-*
%{_datadir}/icons/hicolor/scalable/apps/removable-drives*
%{_datadir}/icons/hicolor/24x24/actions/cinnamon-hc-*
%{_datadir}/xdg-desktop-portal/x-cinnamon-portals.conf
/etc/pam.d/cinnamon
/etc/xdg/menus/cinnamon-applications*
%{python3_sitelib}/cinnamon/

%changelog
* Tue Oct 06 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-4.el10
- Make the TimezoneMap GI namespace optional in cs_calendar.py. Rocky 10
  has no gir1.2-timezonemap package (Linux Mint import), so the hard
  gi.require_version('TimezoneMap', '1.0') at module import crashed
  cinnamon-settings (System Settings) at startup with
  "ValueError: Namespace TimezoneMap not available" (TASK-0021 root
  cause). With the namespace absent, the map widget is skipped and the
  Region/City selector covers timezone selection; behavior is unchanged
  when the namespace is present (TASK-0026).
- Require python3-requests and python3-pexpect: the settings app imports
  both at module level (harvester.py:16, cs_user.py:10), unguarded
  (TASK-0038).
* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-3.el10
- Also require python3-xapp: cinnamon-settings imports xapp at
  bin/SettingsWidgets.py:10 and xapp.os at cinnamon-settings.py:33
  (TASK-0017)
* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-2.el10
- Require python3-setproctitle, python3-pillow, python3-tinycss2 for the
  Python settings app (cinnamon-settings); matches the Fedora package
  (TASK-0017)
* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-1
- Initial port to Rocky Linux 10
- Patches for gcr-4 API compatibility
- libxdo made optional (not available in EL10 repos)
