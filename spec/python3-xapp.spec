Name:           python3-xapp
Version:        3.0.2
Release:        1.el10
Summary:        Xapp Python bindings for Cinnamon settings panels

%global debug_package %{nil}
# No debuginfo subpackage: pure Python (no native debug sections worth shipping)
License:        LGPLv2+
URL:            https://github.com/linuxmint/python3-xapp
Source0:        python3-xapp-3.0.2.tar.gz
# sha256 (GitHub tag 3.0.2 tarball, recorded 2026-09-17 with sha256sum):
# 2078766e2553eea0ff2ee598212d4883a226df63d014d060756c6274db024823

BuildRequires:  meson >= 0.47.0
BuildRequires:  ninja-build
BuildRequires:  python3-devel

# The xapp package wraps the XApp GI bindings; the XApp-1.0 typelib and the
# gi override both come from xapps-lib (our xapps-3.3.3-1.el10 build).
# Version matches the Fedora 44 reference (python3-xapp-3.0.2-2.fc44).
Requires:       python3 >= 3.12
Requires:       python3-gobject
Requires:       xapps-lib
# xapp/os.py imports psutil at module level; EL10 appstream ships
# python3-psutil-5.9.8-6.el10, so no source build is needed.
Requires:       python3-psutil

%description
python3-xapp is the Xapp Python library (the xapp package) used by the
Cinnamon settings application: xapp.SettingsWidgets provides the standard
settings panel widgets, and xapp.os provides the Linux Mint specific
helpers. The Cinnamon settings app imports it at
bin/SettingsWidgets.py:10. Source-built for Rocky Linux 10 because no
EL10 or EPEL repo carries it (TASK-0017).

%prep
%setup -q

%build
# prefix=/usr so meson's python module lands on %{python3_sitelib}
# (the default /usr/local prefix would put it outside the RPM)
meson setup build -Dprefix=/usr

%install
DESTDIR=%{buildroot} ninja -C build install

%files
%license COPYING
%dir %{python3_sitelib}/xapp/
%{python3_sitelib}/xapp/*
# compiled .mo translations from the po/ subdir
/usr/share/locale/*/LC_MESSAGES/python-xapp.mo

%changelog
* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 3.0.2-1.el10
- Source build for the Cinnamon settings app (TASK-0017); version matches
  the Fedora 44 reference
