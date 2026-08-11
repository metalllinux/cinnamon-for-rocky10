Name:           muffin
Version:        6.7.4
Release:        1.el10
Summary:        The Muffin window manager for Cinnamon

License:        GPLv2+
URL:            https://github.com/linuxmint/muffin
Source0:        https://github.com/linuxmint/muffin/archive/refs/tags/%{version}.tar.gz#/muffin-%{version}.tar.gz

BuildRequires:  meson >= 1.0.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconf-pkg-config
BuildRequires:  glib2-devel >= 2.76.0
BuildRequires:  gtk3-devel >= 3.19.8
BuildRequires:  graphene-devel >= 1.9.3
BuildRequires:  gdk-pixbuf2-devel
BuildRequires:  pango-devel
BuildRequires:  pangocairo-devel
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
BuildRequires:  libX11-xcb-devel
BuildRequires:  libxcb-devel
BuildRequires:  libxcb-randr-devel
BuildRequires:  libxcb-res-devel
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
BuildRequires:  wayland-protocols >= 1.38
BuildRequires:  libsystemd-devel
BuildRequires:  upower-glib-devel >= 0.99.0
BuildRequires:  libwacom-devel >= 0.13
BuildRequires:  libudev-devel >= 228
BuildRequires:  gudev-devel >= 232
BuildRequires:  gettext
BuildRequires:  itstool

%description
Muffin is the window manager for the Cinnamon desktop environment. It is
a fork of GNOME Mutter, specifically adapted for Cinnamon's needs. It
includes bundled versions of Clutter and Cogl for rendering.

%package devel
Summary:        Development files for %{name}
Requires:       %{name} = %{version}-%{release}

%description devel
Development files for %{name}.

%package -n muffin-clutter
Summary:        Clutter graphics library bundled with %{name}
Requires:       %{name}-devel = %{version}-%{release}

%description -n muffin-clutter
Clutter graphics library bundled with %{name} for rendering.

%package -n muffin-clutter-devel
Summary:        Development files for muffin-clutter
Requires:       muffin-clutter = %{version}-%{release}

%description -n muffin-clutter-devel
Development files for muffin-clutter.

%package -n muffin-cogl
Summary:        Cogl graphics library bundled with %{name}
Requires:       %{name} = %{version}-%{release}

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
    -Dremote_desktop=auto \
    -Degl_device=true \
    -Dudev=true \
    -Dlibwacom=true \
    -Dpango_ft2=true \
    -Dstartup_notification=true \
    -Dsm=true \
    -Dintrospection=true \
    -Dtests=false \
    -Dprofiler=disabled
%ninja_build

%install
%ninja_install
%find_lang %{name}

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files -f %{name}.lang
%{_bindir}/muffin
%{_libdir}/libmuffin-0.so.*
%{_libexecdir}/muffin
%{_datadir}/muffin
%dir %{_libdir}/muffin
%{_libdir}/muffin/plugins
%{_mandir}/man1/muffin.1*

%files devel
%{_libdir}/libmuffin-0.so
%{_libdir}/pkgconfig/libmuffin-0.pc
%{_includedir}/muffin-0

%files -n muffin-clutter
%{_libdir}/muffin-clutter-0
%{_libdir}/libclutter-1.so.*
%{_libdir}/libclutter-gst-2.0.so.*
%{_libdir}/libclutter-gst-3.0.so.*
%{_libdir}/libclutter-gtk-1.0.so.*
%{_libdir}/libclutter-cogl-1.so.*
%{_libdir}/libclutter-cogl-pango-1.so.*
%{_libdir}/girepository-1.0/Clutter-1.0.typelib
%{_libdir}/girepository-1.0/ClutterCogl-1.0.typelib

%files -n muffin-clutter-devel
%{_libdir}/libclutter-1.so
%{_libdir}/libclutter-gst-2.0.so
%{_libdir}/libclutter-gst-3.0.so
%{_libdir}/libclutter-gtk-1.0.so
%{_libdir}/libclutter-cogl-1.so
%{_libdir}/libclutter-cogl-pango-1.so
%{_libdir}/pkgconfig/clutter-1.0.pc
%{_libdir}/pkgconfig/clutter-gst-2.0.pc
%{_libdir}/pkgconfig/clutter-gst-3.0.pc
%{_libdir}/pkgconfig/clutter-gtk-1.0.pc
%{_libdir}/pkgconfig/clutter-cogl-1.pc
%{_libdir}/pkgconfig/clutter-cogl-pango-1.pc
%{_includedir}/clutter-1.0
%dir %{_libdir}/muffin-clutter-0
%{_libdir}/muffin-clutter-0/*/clutter-*.typelib
%{_libdir}/muffin-clutter-0/clutter-1.0
%{_libdir}/muffin-clutter-0/gi

%files -n muffin-cogl
%{_libdir}/libmuffin-cogl-0.so.*
%{_libdir}/libmuffin-cogl-path-0.so.*
%{_libdir}/libmuffin-cogl-pango-0.so.*

%files -n muffin-cogl-devel
%{_libdir}/libmuffin-cogl-0.so
%{_libdir}/libmuffin-cogl-path-0.so
%{_libdir}/libmuffin-cogl-pango-0.so
%{_libdir}/pkgconfig/muffin-clutter-0.pc
%{_libdir}/pkgconfig/muffin-cogl-0.pc
%{_libdir}/pkgconfig/muffin-cogl-path-0.pc
%{_libdir}/pkgconfig/muffin-cogl-pango-0.pc
%{_includedir}/muffin-clutter-0

%changelog
* Sun Aug 09 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-1
- Initial port to Rocky Linux 10 from Fedora spec
- cinnamon-desktop-devel required (Phase 2 dependency)
