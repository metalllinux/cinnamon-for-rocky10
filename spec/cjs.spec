Name:           cjs
Version:        6.4.0
Release:        1.el10
Summary:        The Cinnamon JavaScript interpreter

License:        MIT and LGPL-2.0-or-later
URL:            https://github.com/linuxmint/cjs
Source0:        https://github.com/linuxmint/cjs/archive/refs/tags/%{version}.tar.gz#/cjs-%{version}.tar.gz

BuildRequires:  meson >= 0.56.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  pkgconf-pkg-config
BuildRequires:  glib2-devel >= 2.66.0
BuildRequires:  libffi-devel
BuildRequires:  gobject-introspection-devel >= 1.66.0
BuildRequires:  mozjs115-devel
BuildRequires:  cairo-devel
BuildRequires:  sysprof-capture-devel
BuildRequires:  readline-devel
BuildRequires:  dbus-devel
BuildRequires:  gtk3-devel

%description
CJS is the Cinnamon JavaScript interpreter. It is a fork of GNOME's GJS
adapted for the Cinnamon desktop environment. It provides a JavaScript
runtime built on SpiderMonkey and GNOME platform libraries.

%package devel
Summary:        Development files for %{name}
Requires:       %{name} = %{version}-%{release}
Requires:       glib2-devel >= 2.66.0
Requires:       gobject-introspection-devel >= 1.66.0
Requires:       mozjs115-devel

%description devel
Development files for %{name}.

%prep
%setup -q

%build
%meson \
    -Dprofiler=auto \
    -Dreadline=enabled \
    -Dinstalled_tests=false \
    -Dskip_gtk_tests=false \
    -Dskip_dbus_tests=false
%ninja_build

%install
%ninja_install
%find_lang %{name}

%files -f %{name}.lang
%{_bindir}/cjs-console
%{_bindir}/cjs
%{_libdir}/libcjs.so.*
%{_datadir}/cjs-1.0
%{_datadir}/installed-tests/cjs-1.0
%dir %{_libdir}/cjs
%{_libdir}/cjs/*.typelib

%files devel
%{_libdir}/libcjs.so
%{_libdir}/pkgconfig/cjs-1.0.pc
%{_includedir}/cjs-1.0
%{_libdir}/cjs/*.a
%{_libdir}/cjs/*.la

%changelog
* Sun Aug 09 2026 Team Chaotix <chaotix@metallinux.dev> - 6.4.0-1
- Initial port to Rocky Linux 10 from Fedora spec
- mozjs115-devel required (not in EL10 repos, must be built separately)
