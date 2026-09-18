Name:           nemo
Version:        6.7.4
Release:        2.el10
Summary:        The default file manager of the Cinnamon desktop

License:        GPLv3+
URL:            https://github.com/linuxmint/nemo
Source0:        %{name}-%{version}.tar.gz
# Source0 provenance (verified 2026-09-18 by full tree diff against upstream):
#   content = linuxmint/nemo @ 932438fc4767 (2026-07-09, "nemo-desktop: Don't
#   crash/quit in Wayland when the monitor is removed (#3785)"). Upstream does
#   not tag release versions; fetchable content ref (top dir nemo-932438fc4767):
#     https://github.com/linuxmint/nemo/archive/932438fc4767.tar.gz
#   sha256 of this build tarball (git archive, top dir nemo-6.7.4/):
#     b21be178735bfc52657d5d5fae710228913fd8be01ef4c396155221db6d50d9a
Requires:       gtk-layer-shell

BuildRequires:  meson >= 0.64.0
BuildRequires:  gtk-layer-shell-devel
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  pkgconf-pkg-config
BuildRequires:  glib2-devel >= 2.45.7
BuildRequires:  gtk3-devel >= 3.10
BuildRequires:  cinnamon-desktop-devel >= 6.0
BuildRequires:  xapps-devel >= 2.6.0
BuildRequires:  gobject-introspection-devel >= 0.9.5
BuildRequires:  libnotify-devel >= 0.4.3
BuildRequires:  libX11-devel
BuildRequires:  libXext-devel
BuildRequires:  libSM-devel
BuildRequires:  gsettings-desktop-schemas
BuildRequires:  dconf-devel
BuildRequires:  dbus-devel
BuildRequires:  libcanberra-devel
BuildRequires:  taglib-devel
BuildRequires:  libexif-devel
# BuildRequires:  libgda-devel  # not available
# BuildRequires:  gvfs-devel  # not available
BuildRequires:  shared-mime-info
BuildRequires:  desktop-file-utils
# BuildRequires:  gnome-desktop-devel  # not available
# BuildRequires:  librsvg-devel  # not available
# BuildRequires:  pygobject3-devel  # not available
BuildRequires:  gettext
BuildRequires:  yelp-tools

%description
Nemo is the default file manager for the Cinnamon desktop environment.
It is a fork of GNOME's Nautilus, extended with additional features
and configuration options for the Cinnamon experience.

%package devel
Summary:        Development files for %{name}
Requires:       %{name} = %{version}-%{release}

%description devel
Development files for %{name}.

%prep
%setup -q

%build
meson setup builddir \
    --prefix=%{_prefix} \
    --libdir=%{_libdir} \
    --buildtype=plain \
    -Dxmp=false \
    -Dgtk_layer_shell=true \
    -Ddeprecated_warnings=false
ninja -C builddir -j2

%install
DESTDIR=%{buildroot} ninja -C builddir install
: %find_lang %{name} --with-gnome || :

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files
%{_bindir}/nemo*
%{_libexecdir}/nemo-extensions-list
%{_libdir}/libnemo-extension.so.*
%{_libdir}/girepository-1.0/Nemo-3.0.typelib
%{_datadir}/gir-1.0/Nemo-3.0.gir
%{_datadir}/applications/nemo*.desktop
%{_datadir}/dbus-1/services/nemo*
%{_datadir}/glib-2.0/schemas/org.nemo.gschema.xml
%{_datadir}/nemo
%{_datadir}/man/man1/nemo*.1*
%{_datadir}/mime/packages/nemo.xml
%{_datadir}/polkit-1/actions/org.nemo.root.policy
%{_datadir}/gtksourceview-*/language-specs/nemo_*
%{_datadir}/icons/hicolor/*/actions/menu-*.*
%{_datadir}/icons/hicolor/*/actions/nemo-*.*
%{_datadir}/icons/hicolor/*/apps/nemo.*
%{_datadir}/icons/hicolor/*/status/nemo-*.*

%files devel
%{_libdir}/libnemo-extension.so
%{_libdir}/pkgconfig/libnemo-extension.pc
%{_includedir}/nemo

%changelog
* Wed Sep 16 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-2
- Enable the gtk-layer-shell Wayland backend (-Dgtk_layer_shell=true) so
  nemo-desktop renders the desktop background on Cinnamon Wayland instead
  of falling back to the X11 backend (TASK-0017 item 2.1).

* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-1
- Initial port to Rocky Linux 10
- XMP support disabled due to missing exempi dependency
