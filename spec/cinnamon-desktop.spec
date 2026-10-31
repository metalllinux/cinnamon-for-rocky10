Name:           cinnamon-desktop
Version:        6.7.2
Release:        3.el10
Summary:        Cinnamon desktop utility library

License:        GPLv2+ and LGPL2+
URL:            https://github.com/linuxmint/cinnamon-desktop
Source0:        %{name}-%{version}.tar.gz
# Source0 provenance (verified 2026-11-01 by full tree diff against upstream):
#   content = linuxmint/cinnamon-desktop @ 934d693ca833 (2026-07-26,
#   "org.cinnamon.desktop.keybindings.gschema: Add 'show-panels'
#   keybinding setting."). Upstream does not tag release versions;
#   fetchable content ref (top dir cinnamon-desktop-934d693ca833):
#     https://github.com/linuxmint/cinnamon-desktop/archive/934d693ca8336271fc321f30f0b93f7029255129.tar.gz
#   Provenance check: diff -r of the staged Source0 tree against a clean
#   checkout of 934d693ca833 (tracked-clean, what the 6.7.2-3 build
#   verified, TASK-0038). A per-build tarball sha256 is intentionally not
#   recorded: tar metadata differs between git archive runs, so such a
#   hash is not reproducible across builds.
# TASK-0017: render the wallpaper pixbuf onto a window-similar surface so it
# composites on the gtk-layer-shell / Wayland desktop (the pixbuf-derived
# surface from gdk_cairo_surface_create_from_pixbuf renders black).
Patch0:         gnome-bg-wayland-surface.patch

BuildRequires:  meson >= 0.56.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconf-pkg-config
BuildRequires:  glib2-devel >= 2.70
BuildRequires:  gtk3-devel >= 3.3.16
BuildRequires:  gdk-pixbuf2-devel >= 2.22.0
BuildRequires:  gobject-introspection-devel
BuildRequires:  systemd-devel
BuildRequires:  libxml2-devel
BuildRequires:  libcanberra-devel
BuildRequires:  pulseaudio-libs-devel
BuildRequires:  libX11-devel
BuildRequires:  libXext-devel
BuildRequires:  libXrandr-devel
BuildRequires:  xkeyboard-config
BuildRequires:  gettext
BuildRequires:  python3
BuildRequires:  libseccomp-devel
BuildRequires:  fontconfig-devel

%description
Cinnamon desktop utility library providing shared functionality
for Cinnamon desktop components including Nemo file manager
and cinnamon-session.

%package devel
Summary:        Development files for %{name}
Requires:       %{name} = %{version}-%{release}

%description devel
Development files for %{name}.

%prep
%setup -q
%patch0 -p1

%build
meson setup builddir \
    --prefix=%{_prefix} \
    --libdir=%{_libdir} \
    --buildtype=plain \
    -Dsystemd=enabled \
    -Ddeprecation_warnings=false
ninja -C builddir -j2

%install
DESTDIR=%{buildroot} ninja -C builddir install
: %find_lang %{name} || :

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files
%license COPYING COPYING.LIB
%{_libdir}/libcinnamon-desktop.so.4*
%{_libdir}/libcvc.so.0*
%{_datadir}/locale
%{_libdir}/girepository-1.0/CDesktopEnums-3.0.typelib
%{_libdir}/girepository-1.0/CinnamonDesktop-3.0.typelib
%{_libdir}/girepository-1.0/Cvc-1.0.typelib
%{_datadir}/gir-1.0/CDesktopEnums-3.0.gir
%{_datadir}/gir-1.0/CinnamonDesktop-3.0.gir
%{_datadir}/gir-1.0/Cvc-1.0.gir
%{_datadir}/glib-2.0/schemas/org.cinnamon.desktop.*.gschema.xml
%{_datadir}/glib-2.0/schemas/org.cinnamon.desktop.enums.xml

%files devel
%{_includedir}/cinnamon-desktop
%{_libdir}/pkgconfig/cinnamon-desktop.pc
%{_libdir}/pkgconfig/cvc.pc
%{_libdir}/libcinnamon-desktop.so
%{_libdir}/libcvc.so

%changelog
* Sun Nov 01 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.2-3
- Rebuild from the tip spec so the package ships the license text declared
  by %license (COPYING, COPYING.LIB)

* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.2-2
- TASK-0017: fix black wallpaper on Wayland by rendering the pixbuf onto a
  window-similar surface (gnome-bg-wayland-surface.patch)
- Re-enable the debuginfo/debugsource subpackages (a stray
  "%global debug_package %{nil}" had dropped them from the 2.el10 build;
  every other C package in the tree ships them)

* Sun Aug 09 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.2-1
- Initial port to Rocky Linux 10 from Fedora spec
