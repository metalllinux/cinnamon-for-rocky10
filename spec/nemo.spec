Name:           nemo
Version:        6.7.4
Release:        1.el10
Summary:        The default file manager of the Cinnamon desktop

License:        GPLv3+
URL:            https://github.com/linuxmint/nemo
Source0:        https://github.com/linuxmint/nemo/archive/refs/tags/%{version}.tar.gz#/nemo-%{version}.tar.gz

BuildRequires:  meson >= 0.64.0
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
BuildRequires:  libgda-devel
BuildRequires:  gvfs-devel
BuildRequires:  shared-mime-info
BuildRequires:  desktop-file-utils
BuildRequires:  gnome-desktop-devel
BuildRequires:  librsvg-devel
BuildRequires:  pygobject3-devel
BuildRequires:  gettext
BuildRequires:  yelp-tools

%description
Nemo is the default file manager for the Cinnamon desktop environment.
It is a fork of GNOME's Nautilus, extended with additional features
and configuration options for the Cinnamon experience.

%package -n %{name}-audio-braille
Summary:        Audio braille plugin for %{name}
Requires:       %{name} = %{version}-%{release}

%description -n %{name}-audio-braille
Audio braille plugin for %{name}.

%package -n %{name}-emacs
Summary:        Emacs support for %{name}
Requires:       %{name} = %{version}-%{release}

%description -n %{name}-emacs
Emacs support for %{name}.

%package -n %{name}-extensions-archive
Summary:        Archive of extensions for %{name}
Requires:       %{name} = %{version}-%{release}

%description -n %{name}-extensions-archive
Archive of extensions for %{name}.

%package -n %{name}-image-converter
Summary:        Image converter extension for %{name}
Requires:       %{name} = %{version}-%{release}

%description -n %{name}-image-converter
Image converter extension for %{name}.

%package -n %{name}-nmbrowser
Summary:        Network browser extension for %{name}
Requires:       %{name} = %{version}-%{release}

%description -n %{name}-nmbrowser
Network browser extension for %{name}.

%package -n %{name}-preeviewer
Summary:        Previewer extension for %{name}
Requires:       %{name} = %{version}-%{release}

%description -n %{name}-preeviewer
Previewer extension for %{name}.

%package -n %{name}-python
Summary:        Python bindings for %{name}
Requires:       %{name} = %{version}-%{release}

%description -n %{name}-python
Python bindings for %{name}.

%package -n %{name}-search-helpers
Summary:        Search helpers for %{name}
Requires:       %{name} = %{version}-%{release}

%description -n %{name}-search-helpers
Search helpers for %{name}.

%package -n %{name}-tnef
Summary:        TNEF support for %{name}
Requires:       %{name} = %{version}-%{release}

%description -n %{name}-tnef
TNEF support for %{name}.

%package -n %{name}-xmp
Summary:        XMP support for %{name}
Requires:       %{name} = %{version}-%{release}

%description -n %{name}-xmp
XMP support for %{name}.

%package devel
Summary:        Development files for %{name}
Requires:       %{name} = %{version}-%{release}

%description devel
Development files for %{name}.

%prep
%setup -q

%build
%meson \
    -Dxmp=false \
    -Ddeprecated_warnings=false
%ninja_build

%install
%ninja_install
%find_lang %{name} --with-gnome

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files -f %{name}.lang
%{_bindir}/nemo
%{_bindir}/nemo-desktop
%{_bindir}/nemo-file-properties
%{_bindir}/nemo-pathbar-popup
%{_libdir}/libnemo-extension.so.*
%{_libdir}/girepository-1.0/Nemo-6.0.typelib
%{_datadir}/girepository-1.0/Nemo-6.0.gir
%{_datadir}/applications/nemo*.desktop
%{_datadir}/dbus-1/services/org.nemo.*
%{_datadir}/glib-2.0/schemas/org.nemo.*
%{_datadir}/nemo
%{_mandir}/man1/nemo*.1*
%dir %{_libdir}/nemo
%{_libdir}/nemo/extensions-3.0
%{_libdir}/nemo/search-helpers

%files -n %{name}-python
%{_libdir}/nemo/python3

%files devel
%{_libdir}/libnemo-extension.so
%{_libdir}/pkgconfig/nemo-extension-3.0.pc
%{_includedir}/nemo

%changelog
* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.4-1
- Initial port to Rocky Linux 10
- XMP support disabled due to missing exempi dependency
