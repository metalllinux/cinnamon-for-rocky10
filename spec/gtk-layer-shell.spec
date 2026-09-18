Name:           gtk-layer-shell
Version:        0.10.1
Release:        1.el10
Summary:        Use the Layer Shell Wayland protocol with GTK

License:        LGPLv3
URL:            https://github.com/wmww/gtk-layer-shell
Source0:        %{name}-%{version}.tar.gz
# Source0 URL (fetched 2026-09-16):
#   https://github.com/wmww/gtk-layer-shell/archive/refs/tags/v0.10.1.tar.gz
# Source0 sha256: 88c3a3e0a5300532f3d368d5df64838a87f1fb85273f22d41df0a6b8d0ec59c6

BuildRequires:  meson >= 0.54.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconf-pkg-config
BuildRequires:  gtk3-devel
BuildRequires:  wayland-devel
BuildRequires:  wayland-protocols-devel

%description
gtk-layer-shell provides a simple API for using the wlr-layer-shell
Wayland protocol with GTK 3 applications. It lets a GTK window occupy a
full-screen compositor layer (background, overlay, etc.) on Wayland
compositors that implement the layer-shell protocol, such as Cinnamon's
muffin. nemo-desktop links against this library to render the desktop
wallpaper on Cinnamon Wayland; without it, nemo-desktop falls back to the
X11 backend and the background is never composited.

%package devel
Summary:        Development files for %{name}
Requires:       %{name} = %{version}-%{release}
Requires:       gtk3-devel
Requires:       wayland-devel

%description devel
The %{name}-devel package contains the shared library, header files, and
pkg-config file for developing applications that use %{name}.

%prep
%setup -q -n %{name}-%{version}

%build
meson setup builddir \
    --prefix=%{_prefix} \
    --libdir=%{_libdir} \
    --buildtype=plain \
    -Dexamples=false \
    -Ddocs=false \
    -Dtests=false \
    -Dintrospection=false \
    -Dvapi=false
ninja -C builddir -j2

%install
DESTDIR=%{buildroot} ninja -C builddir install

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files
%license LICENSE_LGPL.txt
%doc README.md CHANGELOG.md
%{_libdir}/libgtk-layer-shell.so.0*

%files devel
%{_includedir}/gtk-layer-shell/
%{_libdir}/libgtk-layer-shell.so
%{_libdir}/pkgconfig/gtk-layer-shell-0.pc

%changelog
* Wed Sep 16 2026 Team Chaotix <chaotix@metallinux.dev> - 0.10.1-1
- Initial port to Rocky Linux 10 (TASK-0017 item 2.1): provide the
  gtk-layer-shell Wayland backend so nemo-desktop can render the desktop
  background on Cinnamon Wayland.
