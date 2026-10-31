Name:           muffin
Version:        6.7.4
Release:        4.el10
Summary:        The Muffin window manager for Cinnamon

License:        GPLv2+
URL:            https://github.com/linuxmint/muffin
Source0:        https://github.com/linuxmint/muffin/archive/6ed5907a15ae5614c74682f8c736745f4b3a6fab.tar.gz#/muffin-%{version}.tar.gz
# SHA256: 3cfb730faf2de1a620b3ecb2260c289be7c333fe9cedc90e09dcb47df2ef6701
# Source0 provenance (verified 2026-11-01 by full tree diff against upstream):
#   content = linuxmint/muffin @ 6ed5907a15ae (2026-08-06,
#   "meta-backend-native.c: Handle NULL from xkb_keymap_new_from_names.").
#   Upstream does not tag release versions; the old 6.7.4 tag (whose
#   tarball was recorded as ae881d93b128...) has been deleted upstream, so
#   Source0 pins this fetchable commit ref (top dir
#   muffin-6ed5907a15ae5614c74682f8c736745f4b3a6fab); the # SHA256 above is
#   of that commit tarball and is reproducible from the URL.
#   Provenance check: diff -r of the staged Source0 tree against a clean
#   checkout of 6ed5907a15ae (tracked-clean, what the 6.7.4-4 build
#   verified, TASK-0038).

BuildRequires:  meson >= 1.0.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconf-pkg-config
BuildRequires:  glib2-devel >= 2.76.0
BuildRequires:  gtk3-devel >= 3.19.8
BuildRequires:  graphene-devel >= 1.9.3
BuildRequires:  gdk-pixbuf2-devel
BuildRequires:  pango-devel
BuildRequires:  cairo-devel >= 1.10.0
BuildRequires:  cairo-gobject-devel >= 1.10.0
BuildRequires:  fribidi-devel >= 1.0.0
BuildRequires:  gobject-introspection-devel >= 0.9.5
BuildRequires:  json-glib-devel >= 0.12.0
BuildRequires:  cinnamon-desktop-devel >= 5.3
BuildRequires:  libX11-devel
BuildRequires:  libXcomposite-devel >= 0.4
BuildRequires:  libXcursor-devel
BuildRequires:  libXdamage-devel
BuildRequires:  libXext-devel
BuildRequires:  libXfixes-devel >= 3
BuildRequires:  libXi-devel >= 1.7.4
BuildRequires:  libXrandr-devel >= 1.5.0
BuildRequires:  libXtst-devel
BuildRequires:  libxkbfile-devel
BuildRequires:  libxkbcommon-devel >= 0.4.3
BuildRequires:  libxkbcommon-x11-devel
BuildRequires:  libXrender-devel
BuildRequires:  libxcvt >= 0.1.2
BuildRequires:  libxcb-devel
BuildRequires:  libXinerama-devel
BuildRequires:  libXau-devel
BuildRequires:  atk-devel >= 2.5.3
BuildRequires:  libcanberra-devel >= 0.26
BuildRequires:  dbus-devel
BuildRequires:  startup-notification-devel >= 0.7
BuildRequires:  libGL-devel
BuildRequires:  libGLU-devel
BuildRequires:  libepoxy-devel
BuildRequires:  libdrm-devel
BuildRequires:  libgbm-devel
BuildRequires:  libinput-devel >= 1.19.0
BuildRequires:  wayland-devel >= 1.20
BuildRequires:  wayland-protocols-devel >= 1.38
BuildRequires:  systemd-devel
BuildRequires:  upower-devel >= 0.99.0
BuildRequires:  libwacom-devel >= 0.13
BuildRequires:  libudev-devel >= 228
BuildRequires:  libgudev-devel >= 232
BuildRequires:  gettext
BuildRequires:  itstool

Requires:       muffin-cogl = %{version}-%{release}
Requires:       muffin-clutter = %{version}-%{release}

%description
Muffin is the window manager for the Cinnamon desktop environment. It is
a fork of GNOME Mutter, specifically adapted for Cinnamon's needs. It
includes bundled versions of Clutter and Cogl for rendering.

%package devel
Summary:        Development files for %{name}
Requires:       %{name} = %{version}-%{release}
Requires:       muffin-cogl-devel = %{version}-%{release}
Requires:       muffin-clutter-devel = %{version}-%{release}

%description devel
Development files for %{name}.

%package -n muffin-clutter
Summary:        Clutter graphics library bundled with %{name}

%description -n muffin-clutter
Clutter graphics library bundled with %{name} for rendering.

%package -n muffin-clutter-devel
Summary:        Development files for muffin-clutter
Requires:       muffin-clutter = %{version}-%{release}

%description -n muffin-clutter-devel
Development files for muffin-clutter.

%package -n muffin-cogl
Summary:        Cogl graphics library bundled with %{name}

%description -n muffin-cogl
Cogl graphics library bundled with %{name} for OpenGL abstraction.

%package -n muffin-cogl-devel
Summary:        Development files for muffin-cogl
Requires:       muffin-cogl = %{version}-%{release}

%description -n muffin-cogl-devel
Development files for muffin-cogl.

%prep
%setup -q

%build
%meson \
    -Dopengl=true \
    -Dgles2=true \
    -Degl=true \
    -Dglx=true \
    -Dwayland=true \
    -Dnative_backend=true \
    -Dremote_desktop=true \
    -Degl_device=true \
    -Dudev=true \
    -Dlibwacom=true \
    -Dpango_ft2=true \
    -Dstartup_notification=true \
    -Dsm=true \
    -Dintrospection=true \
    -Dtests=false \
    -Dprofiler=false
ninja -v -C redhat-linux-build -j2

%install
DESTDIR=%{buildroot} ninja -C redhat-linux-build install
%find_lang %{name}

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files -f %{name}.lang
%license COPYING
%{_bindir}/muffin
%{_bindir}/cinnamon-list-windows
%{_libdir}/libmuffin.so.*
%{_libexecdir}/muffin-restart-helper
%dir %{_libdir}/muffin
%{_libdir}/muffin/plugins
%{_libdir}/muffin/Meta-0.gir
%{_libdir}/muffin/Meta-0.typelib
%{_datadir}/applications/muffin.desktop
%{_datadir}/glib-2.0/schemas/org.cinnamon.muffin*.gschema.xml
%{_datadir}/man/man1/muffin.1.gz
/usr/lib/udev/rules.d/61-muffin.rules

%files devel
%{_libdir}/libmuffin.so
%{_libdir}/pkgconfig/libmuffin-0.pc
%{_includedir}/muffin

%files -n muffin-clutter
%license COPYING
%{_libdir}/muffin/libmuffin-clutter-0.so.*
%{_libdir}/muffin/Cally-0.gir
%{_libdir}/muffin/Cally-0.typelib
%{_libdir}/muffin/Clutter-0.gir
%{_libdir}/muffin/Clutter-0.typelib
%{_libdir}/muffin/ClutterX11-0.gir
%{_libdir}/muffin/ClutterX11-0.typelib

%files -n muffin-clutter-devel
%{_libdir}/muffin/libmuffin-clutter-0.so
%{_libdir}/pkgconfig/muffin-clutter-0.pc
%{_libdir}/pkgconfig/muffin-clutter-x11-0.pc
%{_includedir}/muffin/clutter

%files -n muffin-cogl
%license COPYING
%{_libdir}/muffin/libmuffin-cogl-0.so.*
%{_libdir}/muffin/libmuffin-cogl-path-0.so.*
%{_libdir}/muffin/libmuffin-cogl-pango-0.so.*
%{_libdir}/muffin/Cogl-0.gir
%{_libdir}/muffin/Cogl-0.typelib
%{_libdir}/muffin/CoglPango-0.gir
%{_libdir}/muffin/CoglPango-0.typelib

%files -n muffin-cogl-devel
%{_libdir}/muffin/libmuffin-cogl-0.so
%{_libdir}/muffin/libmuffin-cogl-path-0.so
%{_libdir}/muffin/libmuffin-cogl-pango-0.so
%{_libdir}/pkgconfig/muffin-cogl-0.pc
%{_libdir}/pkgconfig/muffin-cogl-path-0.pc
%{_libdir}/pkgconfig/muffin-cogl-pango-0.pc

%changelog
* Sun Nov 01 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-4
- Source0: pin the fetchable commit tarball 6ed5907a15ae (the 6.7.4 tag
  was deleted upstream, so the tag tarball no longer exists)
- %license COPYING in muffin-clutter and muffin-cogl so all three runtime
  packages ship the license text declared by the spec

* Thu Aug 13 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-3
- Fix circular dependency: muffin-clutter no longer requires muffin
- Add SHA256 checksum for source
- Replace broad GIR/typelib globs with explicit file names in muffin-clutter
- Move Meta-0 GIR/typelib to main muffin package
- Add Cogl-0 and CoglPango-0 GIR/typelib to muffin-cogl package
- Remove duplicate libX11-devel BuildRequires
- Keep hardcoded udev path (%{_udevdir} not a valid macro on EL10)
- Add explicit Requires on -devel subpackages to muffin-devel

* Thu Aug 13 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-2
- Fix circular dependency: muffin-cogl no longer requires muffin
- Add explicit Requires on muffin-cogl and muffin-clutter to main package
- muffin-clutter requires muffin instead of muffin-devel

* Sun Aug 09 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-1
- Initial port to Rocky Linux 10 from Fedora spec
- cinnamon-desktop-devel required (Phase 2 dependency)
