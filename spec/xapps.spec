Name:           xapps
Version:        3.3.3
Release:        1.el10
Summary:        Shared applications for the Cinnamon desktop environment

License:        GPLv3+
URL:            https://github.com/linuxmint/xapps
Source0:        %{name}-%{version}.tar.gz
# Source0 provenance (verified 2026-09-18 by full tree diff against upstream):
#   content = linuxmint/xapps @ 94a348f16ec3 (2026-07-05, "xapp-sn-watcher:
#   Fix capitalize() mangling non-ASCII titles."). Upstream does not tag
#   release versions; fetchable content ref (top dir xapps-94a348f16ec3):
#     https://github.com/linuxmint/xapps/archive/94a348f16ec3.tar.gz
#   sha256 of this build tarball (git archive, top dir xapps-3.3.3/):
#     efcd4b4ab9dcede1ac79b2b8c5a979a2fdc0d6ac776d27109d602b45c4d7ad86

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

%package -n %{name}-lib
Summary:        Libraries for %{name}
Requires:       glib2

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
meson setup builddir \
    --prefix=%{_prefix} \
    --libdir=%{_libdir} \
    --buildtype=plain \
    -Dapp-lib-only=true \
    -Dvapi=false \
    -Dstatus-notifier=false \
    -Ddeprecated_warnings=false
ninja -C builddir -j2

%install
DESTDIR=%{buildroot} ninja -C builddir install
: %find_lang %{name} --with-gnome || :

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files -n %{name}-lib
%{_libdir}/libxapp.so.*
%{_libdir}/girepository-1.0/XApp-1.0.typelib
%{_datadir}/gir-1.0/XApp-1.0.gir
%{_datadir}/glib-2.0/schemas/org.x.apps.gschema.xml
%{_datadir}/glade/catalogs/xapp-glade-catalog.xml
%{_datadir}/locale
%{_libdir}/python3.12/site-packages/gi/overrides/XApp.py
%{_libdir}/python3.12/site-packages/gi/overrides/__pycache__/XApp*

%files devel
%{_libdir}/libxapp.so
%{_libdir}/pkgconfig/xapp.pc
%{_includedir}/xapp

%changelog
* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 3.3.3-1
- Initial port to Rocky Linux 10
- Built with app-lib-only to minimize dependencies
