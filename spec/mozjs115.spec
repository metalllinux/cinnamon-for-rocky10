%global major 115

# LTO disabled for EL10 to reduce memory pressure
%global build_with_lto    0

Name:           mozjs%{major}
Version:        115.29.0
Release:        1.el10
Summary:        SpiderMonkey JavaScript library

License:        MPL-2.0 AND Apache-2.0 AND BSD-3-Clause AND BSD-2-Clause AND MIT AND GPL-3.0-or-later
URL:            https://developer.mozilla.org/en-US/docs/Mozilla/Projects/SpiderMonkey
Source0:        https://ftp.mozilla.org/pub/firefox/releases/%{version}esr/source/firefox-%{version}esr.source.tar.xz
# SHA256: b3b067c7d520a6527699d89774c44b8647bab9fa76032cd87923d3d22f3ce23c

# Known failures with system libicu
Source1:        known_failures.txt
# SHA256: 678260d2d713a4bc9c1eb9316fe8609b027cecb5d20556cc8f474c1fe63c2e04

# Patches
Patch01:        fix-soname.patch
# SHA256: 02f1902206257a81011545218eef5830a7526fe146230a7727ddb648483007b0
Patch02:        copy-headers.patch
# SHA256: e14cd43729abff2dd895716582f672871eb87643f31d988103768f7d7f286173
Patch09:        icu_sources_data.py-Decouple-from-Mozilla-build-system.patch
# SHA256: 3f61a5258e0b56c0b23835e814e6084eae0b72cb2c3379c71295c9df69b7947a
Patch10:        icu_sources_data-Write-command-output-to-our-stderr.patch
# SHA256: 367fb4b19a5cb9da214716da851d2087cc27662962a27e3b2518380e49f7e6e3
Patch12:        emitter.patch
# SHA256: c64b559714eec2e07b98dd2d35c42f5f0064d05d354d153004678773b488ced2
Patch14:        init_patch.patch
# SHA256: 2f4df2431a8341d08ff122c8bf896186224f7d747594b504eb1de21f414131b7
Patch15:        remove-sloppy-m4-detection-from-bundled-autoconf.patch
# SHA256: d141aff43ea484283ea63187af99eb4f2b7d2094e5f9faa269dfdaec385bbf7a
Patch16:        firefox-112.0-commasplit.patch
# SHA256: 0174ea3524914a5f4434a221861041b978686b622f2a297c3a354f925f44fdbd
Patch17:        six-is-always-PY3-don-t-ask-for-it.patch
# SHA256: 2e51b27387e48d1f6b8bc6570ccdefeb23722c09d2d9194579a5e2b5c637c11e
Patch20:        spidermonkey_checks_disable.patch
# SHA256: db08b6d88ce69ee861d03663805b442bf2c54200c462f5182f18ed13393b4d4b

BuildRequires:  cargo
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  m4
BuildRequires:  make
BuildRequires:  libicu-devel
BuildRequires:  llvm
BuildRequires:  rust
BuildRequires:  rustfmt
BuildRequires:  perl-devel
BuildRequires:  pkgconfig(libffi)
BuildRequires:  pkgconfig(zlib)
BuildRequires:  python3-devel
BuildRequires:  python3-setuptools
BuildRequires:  python3-six
BuildRequires:  readline-devel
BuildRequires:  yasm
BuildRequires:  zip

%description
SpiderMonkey is the code-name for Mozilla Firefox's C++ implementation of
JavaScript. It is intended to be embedded in other applications
that provide host environments for JavaScript.

%package        devel
Summary:        Development files for %{name}
Requires:       %{name}%{?_isa} = %{version}-%{release}

%description    devel
The %{name}-devel package contains libraries and header files for
developing applications that use %{name}.

%prep
%autosetup -n firefox-%{version} -p1

# Purge the bundled six library incompatible with Python 3.12
rm -f third_party/python/six/six.py

# Link the system six library (build tooling expects that)
ln -s /usr/lib/python3.12/site-packages/six.py third_party/python/six/six.py

# Copy out the LICENSE file
cp LICENSE js/src/

# Copy out file containing known test failures with system libicu
cp %{SOURCE1} js/src/

# Remove zlib directory (to be sure using system version)
rm -rf modules/zlib

# Remove unneeded bundled stuff
rm -rf js/src/devtools/automation/variants/
rm -rf js/src/octane/
rm -rf js/src/ctypes/libffi/

%build
# Use bundled autoconf
export M4=m4
export AWK=awk
export AC_MACRODIR=./build/autoconf/

pushd js/src/
%configure \
  --with-system-icu \
  --with-system-zlib \
  --disable-tests \
  --disable-strip \
  --with-intl-api \
  --enable-readline \
  --enable-shared-js \
  --enable-optimize \
  --disable-debug \
  --enable-pie \
  --disable-jemalloc

make -j${RPM_BUILD_NCPUS:-2}

%install
pushd js/src/
make install DESTDIR=%{buildroot}

# Fix permissions
chmod -x %{buildroot}%{_libdir}/pkgconfig/*.pc

# Avoid multilib conflicts
mv %{buildroot}%{_includedir}/mozjs-%{major}/js-config.h \
   %{buildroot}%{_includedir}/mozjs-%{major}/js-config-64.h

cat >%{buildroot}%{_includedir}/mozjs-%{major}/js-config.h <<EOF
#ifndef JS_CONFIG_H_MULTILIB
#define JS_CONFIG_H_MULTILIB

#include <bits/wordsize.h>

#if __WORDSIZE == 32
# include "js-config-32.h"
#elif __WORDSIZE == 64
# include "js-config-64.h"
#else
# error "unexpected value for __WORDSIZE macro"
#endif

#endif
EOF

# Remove unneeded files
rm -f %{buildroot}%{_bindir}/js%{major}-config
rm -f %{buildroot}%{_libdir}/libjs_static.ajs

# Rename library and create symlinks, following fix-soname.patch
mv %{buildroot}%{_libdir}/libmozjs-%{major}.so \
   %{buildroot}%{_libdir}/libmozjs-%{major}.so.0.0.0
ln -s libmozjs-%{major}.so.0.0.0 %{buildroot}%{_libdir}/libmozjs-%{major}.so.0
ln -s libmozjs-%{major}.so.0 %{buildroot}%{_libdir}/libmozjs-%{major}.so

# Copy license documentation to buildroot (path is relative to js/src/, go up two levels)
mkdir -p %{buildroot}%{_datadir}/licenses/mozjs115/
cp -a ../../toolkit/content/license.html %{buildroot}%{_datadir}/licenses/mozjs115/

%files
%doc js/src/README.html
%license js/src/LICENSE
%{_datadir}/licenses/mozjs115/
%{_libdir}/libmozjs-%{major}.so.0*

%files devel
%{_bindir}/js%{major}
%{_libdir}/libmozjs-%{major}.so
%{_libdir}/pkgconfig/*.pc
%{_includedir}/mozjs-%{major}/

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%changelog
* Thu Aug 13 2026 Team Chaotix <chaotix@metallinux.dev> - 115.29.0-1
- Build mozjs115 115.29.0 runtime RPM from Mozilla source
- Adapted Fedora 44 mozjs115.spec for Rocky Linux 10
- ICU 74 compatible (EL10)
- Tests disabled to reduce build time
- LTO disabled to reduce memory pressure
- Build with -j2 to avoid OOM
