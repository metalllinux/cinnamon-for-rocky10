Name:      libxcvt
Version:   0.1.2
Release:   11.el10
Summary:   VESA CVT standard timing modelines generator

URL:       https://gitlab.freedesktop.org/xorg/lib/libxcvt/
Source0:   libxcvt-0.1.2.tar.xz

License:   MIT AND HPND-sell-variant

BuildRequires: gcc
BuildRequires: git
BuildRequires: meson

%description
libxcvt is a library providing a standalone version of the X server
implementation of the VESA CVT standard timing modelines generator.

%package devel
Summary: Development package
Requires: pkgconfig
Requires: libxcvt%{?_isa} = %{version}-%{release}

%description devel
The %{name}-devel package contains libraries and header files for
developing applications that use %{name}.

%package -n cvt
Summary: Command line tool to calculate VESA CVT mode lines
Conflicts: xorg-x11-server-Xorg < 1.21
Requires: libxcvt%{?_isa} = %{version}-%{release}

%description -n cvt
A standalone version of the command line tool cvt copied from the Xorg
implementation and is meant to be a direct replacement to the version
provided by the Xorg server.

%prep
%autosetup -S git_am -n %{name}-%{version}

%build
%meson
%meson_build

%install
%meson_install

%files
%license COPYING
%{_libdir}/libxcvt.so.*

%files devel
%license COPYING
%{_libdir}/pkgconfig/libxcvt.pc
%dir %{_includedir}/libxcvt
%{_includedir}/libxcvt/*.h
%{_libdir}/libxcvt.so

%files -n cvt
%license COPYING
%{_bindir}/cvt
%{_mandir}/man1/cvt.1*

%changelog
* Sat Nov 07 2026 Team Chaotix <chaotix@metallinux.dev> - 0.1.2-11.el10
- Ship the tarball COPYING (MIT, Luc Verhaegen) as %%license in the
  libxcvt, cvt, and devel subpackages; the libxcvt copy moves from
  %doc to %%license so the text lands in /usr/share/licenses/.
* Tue Nov 03 2026 Team Chaotix <chaotix@metallinux.dev> - 0.1.2-10.el10
- Rocky Linux 10 port of libxcvt 0.1.2-12.fc45 (Fedora 45, koji build
  3043445, spec ref 27245553cecb9de30ccc95e32247a9d70286ad94). The cvt
  subpackage is kept: upstream meson builds and installs the cvt binary
  unconditionally and there is no option to disable it. The release is
  10.el10, above the 9.el10 that Rocky 10 AppStream carries for the same
  upstream 0.1.2, so a consumer dnf install upgrades the AppStream
  package in place.
