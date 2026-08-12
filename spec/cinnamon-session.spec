Name:           cinnamon-session
Version:        6.7.3
Release:        1.el10
Summary:        The Cinnamon desktop session manager

License:        GPLv2+
URL:            https://github.com/linuxmint/cinnamon-session
Source0:        https://github.com/linuxmint/cinnamon-session/archive/refs/tags/%{version}.tar.gz#/cinnamon-session-%{version}.tar.gz

BuildRequires:  meson >= 0.56.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconf-pkg-config
BuildRequires:  glib2-devel >= 2.37.3
BuildRequires:  gtk3-devel >= 3.0
BuildRequires:  pango-devel
BuildRequires:  libcanberra-devel >= 0.1
BuildRequires:  libSM-devel
BuildRequires:  libICE-devel
BuildRequires:  libX11-devel
BuildRequires:  libXext-devel
BuildRequires:  libXau-devel
BuildRequires:  libXcomposite-devel
BuildRequires:  libglvnd-devel
BuildRequires:  cinnamon-desktop-devel >= 6.0
BuildRequires:  xapps-devel >= 1.0.4
BuildRequires:  systemd-devel
BuildRequires:  dbus-devel
BuildRequires:  xorg-x11-xtrans-devel
BuildRequires:  gettext

%description
Cinnamon session manager handles desktop session startup, shutdown,
and application autostart for the Cinnamon desktop environment.

%prep
%setup -q

%build
%meson \
    -Dsystemd=auto \
    -Dfrequent_warnings=false
%ninja_build

%install
%ninja_install
%find_lang %{name}

%files -f %{name}.lang
%{_bindir}/cinnamon-session
%{_bindir}/cinnamon-session-calculate-display-type
%{_bindir}/cinnamon-session-debug
%{_bindir}/cinnamon-session-launch-desktop
%{_bindir}/cinnamon-session-quit
%{_bindir}/cinnamon-session-restart-x
%{_bindir}/cinnamon-session-workspaces-client
%{_libexecdir}/cinnamon-session
%{_datadir}/applications/cinnamon*.desktop
%{_datadir}/cinnamon-session
%{_datadir}/glib-2.0/schemas/org.cinnamon.desktop.session*.gschema.xml
%dir %{_libdir}/cinnamon-session
%{_libdir}/cinnamon-session/bin
%{_libdir}/cinnamon-session/libexec
%{_mandir}/man1/cinnamon-session*.1*

%changelog
* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.3-1
- Initial port to Rocky Linux 10
