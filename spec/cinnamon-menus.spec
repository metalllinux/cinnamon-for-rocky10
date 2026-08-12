Name:           cinnamon-menus
Version:        6.7.0
Release:        1.el10
Summary:        Cinnamon menus library

License:        GPLv2+ and LGPL2+
URL:            https://github.com/linuxmint/cinnamon-menus
Source0:        https://github.com/linuxmint/cinnamon-menus/archive/refs/tags/%{version}.tar.gz#/cinnamon-menus-%{version}.tar.gz

BuildRequires:  meson >= 0.56.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconf-pkg-config
BuildRequires:  glib2-devel >= 2.37.3
BuildRequires:  gobject-introspection-devel >= 0.9.5
BuildRequires:  gettext

%description
Cinnamon menus library providing a GTK+ menu model for the Cinnamon
desktop environment.

%package devel
Summary:        Development files for %{name}
Requires:       %{name} = %{version}-%{release}

%description devel
Development files for %{name}.

%prep
%setup -q

%build
%meson \
    -Denable_debug=false \
    -Ddeprecated_warnings=false \
    -Denable_docs=false
%ninja_build

%install
%ninja_install
%find_lang %{name}

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files -f %{name}.lang
%{_libdir}/libcinnamon-menu-3.so.*
%{_libdir}/girepository-1.0/Menu-3.0.typelib
%{_datadir}/gir-1.0/Menu-3.0.gir

%files devel
%{_libdir}/libcinnamon-menu-3.so
%{_libdir}/pkgconfig/libcinnamon-menu-3.0.pc
%{_includedir}/cinnamon-menus-3.0

%changelog
* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.0-1
- Initial port to Rocky Linux 10
