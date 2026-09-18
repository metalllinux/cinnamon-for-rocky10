Name:           python3-tinycss2
Version:        1.5.1
Release:        2.el10
Summary:        CSS tokenizer and parser (CSS 3)

%global debug_package %{nil}
# No debuginfo subpackage: pip-installed module (no native debug sections worth shipping)
License:        BSD-3-Clause
URL:            https://github.com/Kozea/tinycss2
Source0:        tinycss2-1.5.1.tar.gz
# sha256 (PyPI sdist, verified 2026-09-17 with sha256sum):
# d339d2b616ba90ccce58da8495a78f46e55d4d25f9fd71dfd526f07e7d53f957
# Build backend, vendored because no EL10 package provides it. Pinned
# wheel from PyPI (satisfies the sdist's "flit_core >=3.2,<4"); 3.12.0 is
# the latest 3.x release. Unpacked at build time and exposed to pip via
# PYTHONPATH so the PEP 517 backend runs without --build-isolation, i.e.
# with no network access and no unpinned fetch (Omega TASK-0017).
Source1:        flit_core-3.12.0-py3-none-any.whl
# sha256 (PyPI wheel, verified 2026-09-18 with sha256sum):
# e7a0304069ea895172e3c7bb703292e992c5d1555dd1233ab7b5621b5b69e62c

BuildRequires:  python3-devel
BuildRequires:  python3-pip

# The Cinnamon settings app imports this unguarded at modules/cs_themes.py:5
# (theme panel CSS-override handling); bin/CinnamonGtkSettings.py:7 is the
# one already-guarded import, upstream. Version matches the Fedora 44
# reference (python3-tinycss2-1.5.1-2.fc44).
Requires:       python3 >= 3.12
# Importing tinycss2 pulls in tinycss2/ast.py, which does
# `from webencodings import ascii_lower` at module level (ast.py:8, verified
# in the 1.5.1 sdist). rpmbuild does not parse pip dist-info METADATA into
# RPM Requires, so the runtime dependency must be declared here
# (Omega TASK-0017).
Requires:       python3-webencodings

%description
tinycss2 is a CSS tokenizer and parser for CSS 3, conforming to the W3C CSS
Syntax and Parsing specification. Required by the Cinnamon settings theme
panel, which imports it unguarded. Source-built for Rocky Linux 10 because
no EL10 or EPEL repo carries it (TASK-0017).

%prep
%setup -q -n tinycss2-1.5.1

%build
# Pure Python package; nothing to compile.

%install
# EL10's reduced python3-rpm-macros has no pyproject install macro, so
# install with pip into the site-packages target. --no-deps: the single
# runtime dependency (webencodings >= 0.4) is declared as an RPM Requires
# above; rpmbuild does not parse pip dist-info METADATA. --no-build-isolation:
# the flit_core backend is vendored as Source1 (unpacked into backends/
# below) so pip imports it from PYTHONPATH instead of creating an isolated
# environment and fetching an unpinned flit_core from PyPI.
install -d %{buildroot}%{python3_sitelib}
mkdir -p backends
(cd backends && python3 -m zipfile -e %{_sourcedir}/flit_core-3.12.0-py3-none-any.whl .)
PYTHONPATH="$PWD/backends" python3 -m pip install --no-cache-dir --no-deps --no-build-isolation --target %{buildroot}%{python3_sitelib} .

%files
%license LICENSE
%dir %{python3_sitelib}/tinycss2/
%{python3_sitelib}/tinycss2/*
%{python3_sitelib}/tinycss2-1.5.1.dist-info/

%changelog
* Fri Sep 18 2026 Team Chaotix <chaotix@metallinux.dev> - 1.5.1-2.el10
- Ship the BSD-3-Clause license file (Omega TASK-0017); pin the flit_core
  build backend as a vendored Source1 wheel and build with
  --no-build-isolation so no unpinned package is fetched from PyPI at build
  time (Omega TASK-0017)

* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 1.5.1-1.el10
- Source build for the Cinnamon settings app (TASK-0017); version matches
  the Fedora 44 reference
