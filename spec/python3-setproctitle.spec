Name:           python3-setproctitle
Version:        1.3.7
Release:        2.el10
Summary:        Replace the process title of a Python process

%global debug_package %{nil}
# No debuginfo subpackage: pip-installed module (no native debug sections worth shipping)
License:        BSD-3-Clause
URL:            https://github.com/dvarrazzo/py-setproctitle
Source0:        setproctitle-1.3.7.tar.gz
# sha256 (PyPI sdist, verified 2026-09-17 with sha256sum):
# bc2bc917691c1537d5b9bca1468437176809c7e11e5694ca79a9ca12345dcb9e

BuildRequires:  gcc
BuildRequires:  python3-devel
BuildRequires:  python3-pip
# bdist_wheel for the legacy setup.py path with --no-build-isolation
# (in an isolated environment pip would install wheel implicitly)
BuildRequires:  python3-wheel

# The Cinnamon settings app imports this at cinnamon-settings.py:11
# (unguarded) and calls setproctitle("cinnamon-settings") at line 813.
# Version matches the Fedora 44 reference (python3-setproctitle-1.3.7-4.fc44).
Requires:       python3 >= 3.12

%description
setproctitle allows a Python process to change its process title (what is
shown in ps/top) to an arbitrary string. Required by the Cinnamon settings
application (shipped in the cinnamon shell package), which imports it
unguarded at startup. Source-built for Rocky Linux 10 because no EL10 or
EPEL repo carries it (TASK-0017).

%prep
%setup -q -n setproctitle-1.3.7

%build
# No explicit build step; the C extension is compiled by pip in the install step.

%install
# EL10's reduced python3-rpm-macros has no pyproject install macro, so
# with pip into the site-packages target. --no-deps: the sdist declares no
# runtime dependencies (verified against the PyPI metadata). The sdist's
# pyproject.toml has no [build-system] table (legacy setup.py path, no
# build dependencies); --no-build-isolation skips the isolated environment
# entirely, so the build needs no network access at all. The bdist_wheel
# command comes from the BR'd python3-wheel package (EL10's setuptools
# 69.0.3 predates the built-in bdist_wheel).
python3 -m pip install --no-cache-dir --no-deps --no-build-isolation --target %{buildroot}%{python3_sitelib} .

%files
%license LICENSE
%{python3_sitelib}/setproctitle*

%changelog
* Fri Sep 18 2026 Team Chaotix <chaotix@metallinux.dev> - 1.3.7-2.el10
- Ship the BSD-3-Clause license file (Omega TASK-0017); build with
  --no-build-isolation so the build needs no network access (Omega
  TASK-0017)

* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 1.3.7-1.el10
- Source build for the Cinnamon settings app (TASK-0017); version matches
  the Fedora 44 reference
