Name:           gdk-pixbuf-parsers
Version:        2.42.12
Release:        1.el10
Summary:        PNG and JPEG image parsers for gdk-pixbuf
License:        LGPL-2.1-or-later
URL:            https://gitlab.gnome.org/GNOME/gdk-pixbuf
# Loaders API version used by gdk-pixbuf 2.42.x
%global loaders_ver 2.10.0

Source0:        %{name}-%{version}.tar.gz

# Sources are prebuilt objects; no debuginfo/debugsource to generate
%global debug_package %{nil}
%global _enable_debug_sources 0

# The parsers are loaded by the base gdk-pixbuf runtime
Requires:       gdk-pixbuf2

%description
PNG and JPEG image parsers (gdk-pixbuf loaders) required for decoding
the Rocky default wallpaper on the Cinnamon desktop. The base
gdk-pixbuf2 package on this system does not ship the PNG/JPEG parsers,
so the wallpaper image cannot be decoded and the background renders
black. This package supplies the two parsers and regenerates the
gdk-pixbuf loaders cache at install time.

%prep
# Extract the source tarball (prebuilt shared objects) into the build dir
%setup -q

%build
# Prebuilt; no compile step.
:

%install
# Install the PNG and JPEG parsers into the gdk-pixbuf loaders directory
mkdir -p %{buildroot}/%{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders
install -m 0755 libpixbufloader-png.so  %{buildroot}/%{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders/
install -m 0755 libpixbufloader-jpeg.so %{buildroot}/%{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders/

# Ship the cache-regeneration helper under a package-private path so it
# never collides with the one owned by gdk-pixbuf2-devel
mkdir -p %{buildroot}/%{_libexecdir}/%{name}
install -m 0755 gdk-pixbuf-query-loaders %{buildroot}/%{_libexecdir}/%{name}/

# Regenerate the gdk-pixbuf loaders cache so the new parsers are discoverable
%post
%{_libexecdir}/%{name}/gdk-pixbuf-query-loaders > %{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders.cache

%files
%{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders/libpixbufloader-png.so
%{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders/libpixbufloader-jpeg.so
%{_libexecdir}/%{name}/gdk-pixbuf-query-loaders

%changelog
* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 2.42.12-1
- TASK-0017: add PNG and JPEG gdk-pixbuf parsers so the Rocky default
  wallpaper can be decoded and rendered on the Cinnamon Wayland desktop
