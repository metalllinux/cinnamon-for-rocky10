Name:           python3-pillow
Version:        12.3.0
Release:        1.el10
Summary:        Python imaging library (PIL)

%global debug_package %{nil}
# No debuginfo subpackage: pip-installed module (no native debug sections worth shipping)
License:        HPND and MIT
URL:            https://github.com/python-pillow/Pillow
Source0:        pillow-12.3.0.tar.gz
# sha256 (PyPI sdist, verified 2026-09-17 with sha256sum):
# 3b8182a766685eaa002637e28b4ec8d6b18819a0c71f579bf0dbaa5830297cce

BuildRequires:  gcc
BuildRequires:  python3-devel
BuildRequires:  python3-pip
BuildRequires:  libjpeg-turbo-devel
BuildRequires:  libpng-devel
# EL10 ships zlib as zlib-ng; the compat devel package provides <zlib.h>
BuildRequires:  zlib-ng-compat-devel

# The Cinnamon settings app imports PIL unguarded in bin/imtools.py:21-24,
# bin/eyedropper.py:6, modules/cs_backgrounds.py:16, modules/cs_user.py:17
# (wallpaper previews, the color eyedropper, user panel image handling).
# Built against libjpeg + libpng + zlib so JPEG/PNG support matches the
# Fedora 44 reference (python3-pillow-12.3.0-1.fc44).
Requires:       python3 >= 3.12

%description
Pillow (PIL) is the standard Python imaging library: image loading,
manipulation, and saving for JPEG, PNG, and other formats. Required by the
Cinnamon settings application, which imports it unguarded in the background,
eyedropper, and user modules. Source-built for Rocky Linux 10 because no
EL10 or EPEL repo carries it (TASK-0017).

%prep
%setup -q -n pillow-12.3.0

%build
# No explicit build step; the C extension is compiled by pip in the install
# step, against libjpeg-turbo, libpng, and zlib.

%install
# EL10's reduced python3-rpm-macros has no pyproject install macro, so
# with pip into the site-packages target. --no-deps: Pillow declares no
# runtime dependencies. pip verifies the build-dependency hashes against
# PyPI.
python3 -m pip install --no-cache-dir --no-deps --target %{buildroot}%{python3_sitelib} .

%files
%license LICENSE
# Import package is PIL; the dist-info directory uses the PEP 503
# normalized project name (pillow).
%dir %{python3_sitelib}/PIL/
%{python3_sitelib}/PIL/*
%{python3_sitelib}/pillow-12.3.0.dist-info/

%changelog
* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 12.3.0-1.el10
- Source build for the Cinnamon settings app (TASK-0017); version matches
  the Fedora 44 reference; JPEG/PNG support enabled
