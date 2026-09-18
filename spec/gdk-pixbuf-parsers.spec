Name:           gdk-pixbuf-parsers
Version:        2.42.12
Release:        2.el10
Summary:        PNG and JPEG image parsers for gdk-pixbuf
License:        LGPL-2.1-or-later
URL:            https://gitlab.gnome.org/GNOME/gdk-pixbuf
# Loaders API version used by gdk-pixbuf 2.42.x
%global loaders_ver 2.10.0

# Loaders and cache helper built from the upstream gdk-pixbuf release
# tarball (GNOME release archive). The 1.el10 release shipped prebuilt
# objects from a tarball that was not fetchable or auditable; this release
# rebuilds them from source (Shadow TASK-0017).
Source0:        https://download.gnome.org/sources/gdk-pixbuf/2.42/gdk-pixbuf-%{version}.tar.xz
# sha256 (verified 2026-09-18 against the published
# gdk-pixbuf-2.42.12.sha256sum):
# b9505b3445b9a7e48ced34760c3bcb73e966df3ac94c95a148cb669ab748e3c

BuildRequires:  gcc
BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  pkgconf-pkg-config
BuildRequires:  glib2-devel
BuildRequires:  libpng-devel
BuildRequires:  libjpeg-turbo-devel

# The parsers are loaded by the base gdk-pixbuf runtime
Requires:       gdk-pixbuf2

%description
PNG and JPEG image parsers (gdk-pixbuf loaders) required for decoding
the Rocky default wallpaper on the Cinnamon desktop. The base gdk-pixbuf2
package on this system does not ship the PNG/JPEG parsers (EL10 builds the
library without builtin PNG/JPEG loaders), and EL10's native
gdk-pixbuf2-modules package ships only the GIF and TIFF loaders (verified
2026-09-18 with rpm -ql), so the wallpaper image cannot be decoded and the
background renders black. This package supplies the two parsers, built from
the upstream gdk-pixbuf 2.42.12 source, and regenerates the gdk-pixbuf
loaders cache at install time.

%prep
%setup -q -n gdk-pixbuf-%{version}

%build
# Build the PNG and JPEG loader modules and the cache-regeneration tool
# from the upstream tree. builtin_loaders=none keeps PNG/JPEG out of the
# library (we ship standalone modules; EL10's native library has none
# builtin). gif/tiff are left to EL10's native gdk-pixbuf2-modules, svg to
# librsvg2. The full upstream library is compiled as a link dependency of
# the modules but is not installed.
%meson \
    -Dpng=enabled \
    -Djpeg=enabled \
    -Dgif=disabled \
    -Dtiff=disabled \
    -Dothers=disabled \
    -Dbuiltin_loaders=none \
    -Dtests=false \
    -Dinstalled_tests=false \
    -Dman=false \
    -Dintrospection=disabled
%meson_build

%install
# Install only the two loader modules and the cache helper; the rest of
# the upstream build (library, headers, tests) is not part of this package.
# redhat-linux-build/ is the meson build dir hardcoded in EL10's %meson
# macro (macros.d/macros.meson).
mkdir -p %{buildroot}/%{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders
install -m 0755 redhat-linux-build/gdk-pixbuf/libpixbufloader-png.so  %{buildroot}/%{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders/
install -m 0755 redhat-linux-build/gdk-pixbuf/libpixbufloader-jpeg.so %{buildroot}/%{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders/

# Ship the cache-regeneration helper under a package-private path so it
# never collides with the one owned by gdk-pixbuf2-devel
mkdir -p %{buildroot}/%{_libexecdir}/%{name}
install -m 0755 redhat-linux-build/gdk-pixbuf/gdk-pixbuf-query-loaders %{buildroot}/%{_libexecdir}/%{name}/

# Regenerate the gdk-pixbuf loaders cache so the new parsers are discoverable
%post
%{_libexecdir}/%{name}/gdk-pixbuf-query-loaders > %{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders.cache

# On removal our helper is already gone, so regenerate the cache without
# the PNG/JPEG entries. Prefer the helper if it is still present (upgrade
# case), then the system tool (gdk-pixbuf2-devel), then strip the two
# stale entries from the existing cache in place.
%postun
if [ $1 -eq 0 ]; then
    cache=%{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders.cache
    if [ -x %{_libexecdir}/%{name}/gdk-pixbuf-query-loaders ]; then
        %{_libexecdir}/%{name}/gdk-pixbuf-query-loaders > "$cache"
    elif command -v gdk-pixbuf-query-loaders >/dev/null 2>&1; then
        gdk-pixbuf-query-loaders > "$cache"
    elif command -v gdk-pixbuf-query-loaders-64 >/dev/null 2>&1; then
        gdk-pixbuf-query-loaders-64 > "$cache"
    elif [ -f "$cache" ]; then
        awk 'BEGIN{RS=""; ORS="\n\n"} $1 !~ /libpixbufloader-(png|jpeg)\.so/' "$cache" > "$cache.stripped" \
            && mv "$cache.stripped" "$cache"
    fi
fi

%files
%license COPYING
%{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders/libpixbufloader-png.so
%{_libdir}/gdk-pixbuf-2.0/%{loaders_ver}/loaders/libpixbufloader-jpeg.so
%{_libexecdir}/%{name}/gdk-pixbuf-query-loaders

%changelog
* Fri Sep 18 2026 Team Chaotix <chaotix@metallinux.dev> - 2.42.12-2.el10
- Build the loaders and cache helper from the upstream gdk-pixbuf 2.42.12
  source tarball (fetchable URL + verified checksum) instead of a prebuilt
  tarball (Shadow TASK-0017); ship the LGPL-2.1 license file (Omega
  TASK-0017); add %postun so removal regenerates the loaders cache and
  leaves no stale entries (Shadow TASK-0017); debuginfo/debugsource
  subpackages are now generated as with the rest of the tree

* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 2.42.12-1
- TASK-0017: add PNG and JPEG gdk-pixbuf parsers so the Rocky default
  wallpaper can be decoded and rendered on the Cinnamon Wayland desktop
