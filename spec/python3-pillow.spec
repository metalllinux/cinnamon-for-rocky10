Name:           python3-pillow
Version:        12.3.0
Release:        2.el10
Summary:        Python imaging library (PIL)

%global debug_package %{nil}
# No debuginfo subpackage: pip-installed module (no native debug sections worth shipping)
License:        HPND and MIT
URL:            https://github.com/python-pillow/Pillow
Source0:        pillow-12.3.0.tar.gz
# sha256 (PyPI sdist, verified 2026-09-17 with sha256sum):
# 3b8182a766685eaa002637e28b4ec8d6b18819a0c71f579bf0dbaa5830297cce
# Build backends, vendored because the sdist's PEP 517 table
# (requires = ["pybind11", "setuptools>=77"]) cannot be satisfied from EL10
# packages (EL10 ships setuptools 69.0.3, no pybind11) and must not be
# fetched unpinned from PyPI at build time (Omega TASK-0017). Pinned
# wheels from PyPI; setuptools 84.0.0 satisfies the >=77 requirement,
# pybind11 3.1.0 provides the setup_helpers.ParallelCompile import used by
# setup.py. Unpacked at build time and exposed to pip via PYTHONPATH so
# the in-tree _custom_build backend (a thin wrapper over
# setuptools.build_meta) runs with --no-build-isolation.
Source1:        setuptools-84.0.0-py3-none-any.whl
# sha256 (PyPI wheel, verified 2026-09-18 with sha256sum):
# 51a52592b3b99e102b609654876bd65f19f999935166d1352678931132b0c670
Source2:        pybind11-3.1.0-py3-none-any.whl
# sha256 (PyPI wheel, verified 2026-09-18 with sha256sum):
# b8488090f8acffbcb6b5d6a85571a6827a0a2981ffb75e5a0b27b87c4a6b7dd0

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
# runtime dependencies. --no-build-isolation: the PEP 517 backends
# (setuptools, pybind11) are vendored as Source1/Source2 (unpacked into
# backends/ below) so pip imports them from PYTHONPATH instead of creating
# an isolated environment and fetching unpinned wheels from PyPI. The
# vendored setuptools shadows EL10's 69.0.3 for this build only.
install -d %{buildroot}%{python3_sitelib}
mkdir -p backends
(cd backends && python3 -m zipfile -e %{_sourcedir}/setuptools-84.0.0-py3-none-any.whl . \
    && python3 -m zipfile -e %{_sourcedir}/pybind11-3.1.0-py3-none-any.whl .)
PYTHONPATH="$PWD/backends" python3 -m pip install --no-cache-dir --no-deps --no-build-isolation --target %{buildroot}%{python3_sitelib} .

%files
%license LICENSE
# Import package is PIL; the dist-info directory uses the PEP 503
# normalized project name (pillow).
%dir %{python3_sitelib}/PIL/
%{python3_sitelib}/PIL/*
%{python3_sitelib}/pillow-12.3.0.dist-info/

%changelog
* Fri Sep 18 2026 Team Chaotix <chaotix@metallinux.dev> - 12.3.0-2.el10
- Ship the MIT license file (Omega TASK-0017); pin the setuptools and
  pybind11 build backends as vendored Source1/Source2 wheels and build
  with --no-build-isolation so no unpinned package is fetched from PyPI
  at build time (Omega TASK-0017)

* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 12.3.0-1.el10
- Source build for the Cinnamon settings app (TASK-0017); version matches
  the Fedora 44 reference; JPEG/PNG support enabled
