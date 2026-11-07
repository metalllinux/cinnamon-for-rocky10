Summary: X.Org X11 libXfont2 runtime library
Name: libXfont2
Version: 2.0.9
Release: 1.el10
License: BSD-2-Clause AND BSD-4-Clause-UC AND HPND-sell-variant AND MIT-open-group AND SMLNJ AND X11
URL: http://www.x.org

Source0: libXfont2-2.0.9.tar.xz

BuildRequires: make
BuildRequires: autoconf automake libtool
BuildRequires: pkgconfig(fontsproto)
BuildRequires: xorg-x11-util-macros
BuildRequires: xorg-x11-xtrans-devel >= 1.0.3-3
BuildRequires: libfontenc-devel
BuildRequires: freetype-devel

%description
X.Org X11 libXfont2 runtime library

%package devel
Summary: X.Org X11 libXfont2 development package
Requires: %{name}%{?_isa} = %{version}-%{release}
Requires: libfontenc-devel%{?_isa}

%description devel
X.Org X11 libXfont development package

%prep
%autosetup

%build
autoreconf -v --install --force
export CFLAGS="$RPM_OPT_FLAGS -Os"
%configure --disable-static --disable-fc
make %{?_smp_mflags}  

%install
%make_install

# We intentionally don't ship *.la files
rm -f $RPM_BUILD_ROOT%{_libdir}/*.la

%ldconfig_post
%ldconfig_postun

%files
%license COPYING
%doc AUTHORS README.md ChangeLog
%{_libdir}/libXfont2.so.2*

%files devel
%{_includedir}/X11/fonts/libxfont2.h
%{_libdir}/libXfont2.so
%{_libdir}/pkgconfig/xfont2.pc

%changelog
* Tue Nov 03 2026 Team Chaotix <chaotix@metallinux.dev> - 2.0.9-1.el10
- Rocky Linux 10 port of libXfont2 2.0.9-1.fc45 (Fedora 45, koji build
  3074213, spec ref e87bac79e8155fef29baf71603cdcaa9f9092043). Carries
  CVE-2026-59679 and CVE-2026-44950 fixes.
