Summary:	High-level API for X Keyboard Extension
Name:		libxklavier
Version:	5.4
Release:	2.el10
License:	LGPL-2.0-or-later
URL: http://www.freedesktop.org/wiki/Software/LibXklavier
BuildRequires: make
BuildRequires: libxml2-devel
BuildRequires: libxkbfile-devel
BuildRequires: libX11-devel
BuildRequires: libXi-devel
BuildRequires: libxml2-devel
BuildRequires: glib2-devel >= 2.6.0
BuildRequires: iso-codes-devel
BuildRequires: gobject-introspection-devel
Requires: iso-codes
#Source: http://download.gnome.org/sources/libxklavier/5.3/%{name}-%{version}.tar.xz
Source: libxklavier-5.4.tar.bz2

Patch01: 0001-props-fix-the-max-lengths-for-set_name-description-s.patch
Patch02: 0002-config-use-our-name-description-setter-functions.patch
Patch03: 0003-props-validate-name-and-descriptions-for-valid-UTF-8.patch

%description
libxklavier is a library providing a high-level API for the X Keyboard
Extension (XKB). This library is intended to support XFree86 and other
commercial X servers. It is useful for creating XKB-related software
(layout indicators etc).

%package devel
Summary: Development files for libxklavier
Requires: %{name} = %{version}-%{release}
Requires: libxml2-devel

%description devel
This package contains libraries, header files and developer documentation
needed to develop libxklavier applications.

%prep
%autosetup -p1

%build
%configure \
  --disable-static \
  --with-xkb-base='%{_datadir}/X11/xkb' \
  --with-xkb-bin-base='%{_bindir}'

make V=1 %{?_smp_mflags}


%install
make install DESTDIR=$RPM_BUILD_ROOT

rm -f $RPM_BUILD_ROOT%{_libdir}/*.{a,la}

%ldconfig_post

%ldconfig_postun

%files
%license COPYING.LIB
%doc AUTHORS NEWS README
%{_libdir}/libxklavier.so.16*
%dir %{_libdir}/girepository-1.0
%{_libdir}/girepository-1.0/Xkl-1.0.typelib

%files devel
%license COPYING.LIB
%{_libdir}/pkgconfig/libxklavier.pc
%{_libdir}/libxklavier.so
%{_includedir}/libxklavier/
%{_datadir}/gtk-doc
%dir %{_datadir}/gir-1.0
%{_datadir}/gir-1.0/Xkl-1.0.gir
%dir %{_datadir}/vala/vapi
%{_datadir}/vala/vapi/libxklavier.vapi
%{_datadir}/vala/vapi/libxklavier.deps

%changelog
* Sat Nov 07 2026 Team Chaotix <chaotix@metallinux.dev> - 5.4-2.el10
- Ship the tarball COPYING.LIB (LGPL-2.0) as %%license in the main and
  devel subpackages; the main copy moves from %doc to %%license so the
  text lands in /usr/share/licenses/.
* Tue Nov 03 2026 Team Chaotix <chaotix@metallinux.dev> - 5.4-1.el10
- Rocky Linux 10 port of libxklavier 5.4-31.fc45 (Fedora 45, koji build
  3043440, spec ref 0fa4f60f8e5cef46800989965d5685c193d53518).
