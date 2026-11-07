%global tarball xf86-input-libinput
%global moduledir %(pkg-config xorg-server --variable=moduledir )
%global driverdir %{moduledir}/input

#define gitdate 20160929
%global gitversion 66c997886

Summary:    Xorg X11 libinput input driver
Name:       xorg-x11-drv-libinput
Version:    1.5.0
Release:    2.el10
URL:        http://www.x.org
# SPDX
License:    MIT

Source0:    xf86-input-libinput-1.5.0.tar.xz
Source1:    71-libinput-overrides-wacom.conf

# Fedora-only hack for hidpi screens
# https://bugzilla.redhat.com/show_bug.cgi?id=1413306
Patch01:    0001-Add-a-DPIScaleFactor-option-as-temporary-solution-to.patch

BuildRequires: make
BuildRequires: autoconf automake libtool
BuildRequires: xorg-x11-server-devel >= 1.14.0
BuildRequires: systemd-devel libevdev-devel libinput-devel >= 0.6.0-3
BuildRequires: xorg-x11-util-macros

Requires: Xorg %(xserver-sdk-abi-requires ansic)
Requires: Xorg %(xserver-sdk-abi-requires xinput)
Requires: xkeyboard-config
Requires: libinput >= 0.21.0

Provides: xorg-x11-drv-synaptics = 1.9.0-3
Obsoletes: xorg-x11-drv-synaptics < 1.9.0-3

%description
A generic input driver for the X.Org X11 X server based on libinput,
supporting all devices.

%prep
%autosetup -p 1 -n %{tarball}-%{?gitdate:%{gitdate}}%{!?gitdate:%{version}}

%build
autoreconf --force -v --install || exit 1
%configure --disable-static --disable-silent-rules
make %{?_smp_mflags}

%install
%make_install

# FIXME: Remove all libtool archives (*.la) from modules directory.  This
# should be fixed in upstream Makefile.am or whatever.
find $RPM_BUILD_ROOT -regex ".*\.la$" | xargs rm -f --

cp %{SOURCE1} $RPM_BUILD_ROOT%{_datadir}/X11/xorg.conf.d/

%files
%license COPYING
%{driverdir}/libinput_drv.so
%{_datadir}/X11/xorg.conf.d/40-libinput.conf
%{_datadir}/X11/xorg.conf.d/71-libinput-overrides-wacom.conf
%{_mandir}/man4/libinput.4*

%package devel
Summary:        Xorg X11 libinput input driver development package.
Requires:       pkgconfig
%description devel
Xorg X11 libinput input driver development files.

%files devel
%license COPYING
%{_libdir}/pkgconfig/xorg-libinput.pc
%dir %{_includedir}/xorg/
%{_includedir}/xorg/libinput-properties.h


%changelog
* Sat Nov 07 2026 Team Chaotix <chaotix@metallinux.dev> - 1.5.0-2.el10
- Ship the tarball COPYING (MIT) as %%license in the main and devel
  subpackages; the main copy moves from %doc to %%license so the text
  lands in /usr/share/licenses/.
* Tue Nov 03 2026 Team Chaotix <chaotix@metallinux.dev> - 1.5.0-1.el10
- Rocky Linux 10 port of xorg-x11-drv-libinput 1.5.0-5.fc45 (Fedora 45,
  koji build 3059231, spec ref df802ca3d67e2dbc28c8ed5a905e38c15397184d).
  BuildRequires: libudev-devel renamed to systemd-devel (el10 ships
  libudev.pc in systemd-devel).
