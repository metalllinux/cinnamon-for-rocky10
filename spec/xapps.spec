Name:           xapps
Version:        3.3.3
Release:        1.el10
Summary:        Shared applications for the Cinnamon desktop environment

License:        GPLv3+
URL:            https://github.com/linuxmint/xapps
Source0:        https://github.com/linuxmint/xapps/archive/refs/tags/%{version}.tar.gz#/xapps-%{version}.tar.gz

BuildRequires:  meson >= 0.56.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  pkgconf-pkg-config
BuildRequires:  glib2-devel >= 2.40
BuildRequires:  gtk3-devel >= 3.10
BuildRequires:  gobject-introspection-devel >= 1.50
BuildRequires:  libcanberra-devel >= 0.1
BuildRequires:  libnotify-devel >= 0.6.0
BuildRequires:  libappindicator-gtk3-devel
BuildRequires:  dbus-devel
BuildRequires:  python3-devel
BuildRequires:  gettext

%description
XApps is a set of shared applications and libraries for the Cinnamon
desktop environment, providing status notifier support, tray icon
functionality, and other common components.

%package -n %{name}-common
Summary:        Common files for %{name}
Requires:       %{name}-lib = %{version}-%{release}

%description -n %{name}-common
Common files shared between XApps components.

%package -n %{name}-lib
Summary:        Libraries for %{name}
Requires:       glib2 = %{glib_ver}

%description -n %{name}-lib
Libraries used by %{name}.

%package devel
Summary:        Development files for %{name}
Requires:       %{name}-lib = %{version}-%{release}

%description devel
Development files for %{name}.

%prep
%setup -q

%build
%meson \
    -Dapp-lib-only=true \
    -Dvapi=false \
    -Dstatus-notifier=disabled \
    -Ddeprecated_warnings=false
%ninja_build

%install
%ninja_install
%find_lang %{name} --with-gnome

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files -n %{name}-lib -f %{name}.lang
%{_libdir}/libxapp.so.*
%{_libdir}/girepository-1.0/XApp-1.0.typelib
%{_datadir}/gir-1.0/XApp-1.0.gir
%{_datadir}/glib-2.0/schemas/org.x.app.*

%files -n %{name}-common
%{_libexecdir}/xapps

%files devel
%{_libdir}/libxapp.so
%{_libdir}/pkgconfig/xapp.pc
%{_includedir}/xapp

%changelog
* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 3.3.3-1
- Initial port to Rocky Linux 10
- Built with app-lib-only to minimize dependencies
