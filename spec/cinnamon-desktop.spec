Name:           cinnamon-desktop
Version:        6.7.2
Release:        1.el10
Summary:        Cinnamon desktop utility library

License:        GPLv2+ and LGPL2+
URL:            https://github.com/linuxmint/cinnamon-desktop
Source0:        cinnamon-desktop-6.7.2.tar.gz

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

%build
meson setup builddir --prefix=%{_prefix} --libdir=%{_libdir} \
    -Dsystemd=enabled \
    -Ddeprecation_warnings=false
ninja -C builddir

%install
DESTDIR=%{buildroot} meson install -C builddir
%find_lang %{name}

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files -f %{name}.lang
%{_libdir}/libcinnamon-desktop.so.4*
%{_libdir}/libcinnamon-desktop.so
%{_libdir}/libcvc.so.0*
%{_libdir}/libcvc.so
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

%changelog
* Sun Aug 09 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.2-1
- Initial port to Rocky Linux 10 from Fedora spec
