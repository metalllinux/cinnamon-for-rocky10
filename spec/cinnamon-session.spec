Name:           cinnamon-session
Version:        6.7.3
Release:        1.el10
Summary:        The Cinnamon desktop session manager

License:        GPLv2+
URL:            https://github.com/linuxmint/cinnamon-session
Source0:        %{name}-%{version}.tar.gz
# Source0 provenance (verified 2026-09-18 by full tree diff against upstream):
#   content = linuxmint/cinnamon-session @ 382af0f7e6df (2026-08-10,
#   "csm-manager.c: Move SessionOver emission to a more common location.").
#   Upstream does not tag release versions; fetchable content ref (top dir
#   cinnamon-session-382af0f7e6df):
#     https://github.com/linuxmint/cinnamon-session/archive/382af0f7e6df.tar.gz
#   sha256 of this build tarball (git archive, top dir cinnamon-session-6.7.3/):
#     31aaa7fb84c36babaf29abc46aef7763244b7121755312277678fa5bfaeb96b8

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
meson setup builddir \
    --prefix=%{_prefix} \
    --libdir=%{_libdir} \
    --buildtype=plain \
    -Dsystemd=auto \
    -Dfrequent_warnings=false
ninja -C builddir -j2

%install
DESTDIR=%{buildroot} ninja -C builddir install
: %find_lang %{name} || :

%files
%{_bindir}/cinnamon-session
%{_bindir}/cinnamon-session-quit
%{_libexecdir}/cinnamon-session-binary
%{_libexecdir}/cinnamon-session-check-accelerated
%{_libexecdir}/cinnamon-session-check-accelerated-helper
%{_prefix}/lib/systemd/user/cinnamon-session.target
%{_datadir}/cinnamon-session
%{_datadir}/glib-2.0/schemas/org.cinnamon.SessionManager.gschema.xml
%{_datadir}/icons/hicolor/*/apps/cinnamon-session-properties.*
%{_mandir}/man1/cinnamon-session*.1*

%changelog
* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.3-1
- Initial port to Rocky Linux 10
