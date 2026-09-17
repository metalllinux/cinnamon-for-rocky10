Name:           python3-tinycss2
Version:        1.5.1
Release:        1.el10
Summary:        CSS tokenizer and parser (CSS 3)

%global debug_package %{nil}
# No debuginfo subpackage: pip-installed module (no native debug sections worth shipping)
License:        BSD-3-Clause
URL:            https://github.com/Kozea/tinycss2
Source0:        tinycss2-1.5.1.tar.gz
# sha256 (PyPI sdist, verified 2026-09-17 with sha256sum):
# d339d2b616ba90ccce58da8495a78f46e55d4d25f9fd71dfd526f07e7d53f957

BuildRequires:  python3-devel
BuildRequires:  python3-pip

# The Cinnamon settings app imports this unguarded at modules/cs_themes.py:5
# (theme panel CSS-override handling); bin/CinnamonGtkSettings.py:7 is the
# one already-guarded import, upstream. Version matches the Fedora 44
# reference (python3-tinycss2-1.5.1-2.fc44).
Requires:       python3 >= 3.12

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
# runtime dependency (webencodings >= 0.4) becomes an RPM Requires via the
# dist-info metadata, satisfied by python3-webencodings in this repo. pip
# verifies the build-dependency hashes against PyPI.
python3 -m pip install --no-cache-dir --no-deps --target %{buildroot}%{python3_sitelib} .

%files
%dir %{python3_sitelib}/tinycss2/
%{python3_sitelib}/tinycss2/*
%{python3_sitelib}/tinycss2-1.5.1.dist-info/

%changelog
* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 1.5.1-1.el10
- Source build for the Cinnamon settings app (TASK-0017); version matches
  the Fedora 44 reference
