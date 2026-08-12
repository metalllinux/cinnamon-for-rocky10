Name:           cinnamon
Version:        6.7.4
Release:        1.el10
Summary:        GNOME desktop environment fork providing the Cinnamon experience

License:        GPLv2+ and LGPL2+
URL:            https://github.com/linuxmint/cinnamon
Source0:        %{name}-%{version}.tar.gz

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

%description
Cinnamon is a desktop environment which provides advanced innovative
features on top of the traditional desktop metaphor. It is based on
the GNOME platform, but uses the Muffin window manager instead of
Mutter and CJS instead of GJS for the JavaScript runtime.

%prep
%setup -q

# Patch: make libxdo optional
sed -i 's/xdo = cc.find_library(.xdo.)/xdo = cc.find_library("xdo", required: false)/' meson.build

# Patch: update gcr include paths for gcr-4
sed -i 's|#include <gcr/gcr-base.h>|#include <gcr/gcr.h>|' src/cinnamon-keyring-prompt.c src/cinnamon-secure-text-buffer.c

# Patch: update GcrPromptIface to GcrPromptInterface for gcr-4 compatibility
sed -i 's/GcrPromptIface/GcrPromptInterface/g' src/cinnamon-keyring-prompt.c

# Patch: fix G_DEFINE_TYPE_WITH_CODE syntax
sed -i 's/G_IMPLEMENT_INTERFACE (GCR_TYPE_PROMPT, cinnamon_keyring_prompt_iface);/G_IMPLEMENT_INTERFACE (GCR_TYPE_PROMPT, cinnamon_keyring_prompt_iface))/' src/cinnamon-keyring-prompt.c

# Patch: update GIR include from Gcr-3 to Gcr-4
sed -i "s/'Gcr-3'/'Gcr-4'/" src/meson.build

# Patch: add HAVE_XDO to config.h
sed -i '/if xdo.found()/i\if xdo.found()\n    cinnamon_conf.set10('\''HAVE_XDO'\'', true)\nendif\n' meson.build || true

# Patch: wrap xdo includes with HAVE_XDO guards
sed -i 's|#include <xdo.h>|#ifdef HAVE_XDO\n#include <xdo.h>\n#endif|' src/cinnamon-global-private.h
sed -i 's|#include <xdo.h>|#ifdef HAVE_XDO\n#include <xdo.h>\n#endif|' src/screensaver/backup-locker/event-grabber.c

# Patch: make xdo optional in backup-locker
sed -i 's|dependencies: \[config_h, X11, xcomposite, xext, gtk, glib, gdkx11, xdo\]|dependencies: [config_h, X11, xcomposite, xext, gtk, glib, gdkx11] + (xdo.found() ? [xdo] : [])|' src/screensaver/backup-locker/meson.build

# Patch: make xdo optional in main deps
sed -i '/^    xdo,$/d' src/meson.build

# Patch: lower cjs version requirement (upstream 6.4.0 vs Fedora 115.0)
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
* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-1
- Initial port to Rocky Linux 10
- Patches for gcr-4 API compatibility
- libxdo made optional (not available in EL10 repos)
