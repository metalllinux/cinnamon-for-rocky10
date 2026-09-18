Name:           python3-webencodings
Version:        0.5.1
Release:        1.el10
Summary:        Character encoding aliases for legacy web content

%global debug_package %{nil}
# No debuginfo subpackage: pip-installed module (no native debug sections worth shipping)
License:        BSD
URL:            https://github.com/courtbouillon/webencodings
Source0:        webencodings-0.5.1.tar.gz
# sha256 (PyPI sdist, verified 2026-09-17 with sha256sum):
# b36a1c245f2d304965eb4e0a82848379241dc04b865afcc4aab16748587e1923
# The PyPI sdist ships no license file; Source1 is the upstream BSD license
# vendored from https://raw.githubusercontent.com/courtbouillon/webencodings/v0.5.1/LICENSE
# (fetched 2026-09-18):
Source1:        webencodings-LICENSE
# sha256: f23bae6ada76095610a77137fb92aec7342723900211c5826d54b4c57907ca56

BuildRequires:  python3-devel
BuildRequires:  python3-pip

# Runtime dependency of python3-tinycss2 (tinycss2 1.5.1 declares
# webencodings >= 0.4), which the Cinnamon settings theme panel imports
# unguarded. Version matches the Fedora 44 reference
# (python3-webencodings-0.5.1).
Requires:       python3 >= 3.12

%description
webencodings provides the list of encoding aliases used for web content
(HTML/CSS), including the legacy W3C encoding labels. Required by
python3-tinycss2, which the Cinnamon settings theme panel imports.
Source-built for Rocky Linux 10 because no EL10 or EPEL repo carries it
(TASK-0017).

%prep
%setup -q -n webencodings-0.5.1
# The sdist ships no license file; place the vendored upstream license in the
# build dir so %license below ships it in the package.
install -m 0646 %{_sourcedir}/webencodings-LICENSE LICENSE

%build
# Pure Python package; nothing to compile.

%install
# EL10's reduced python3-rpm-macros has no pyproject install macro, so
# install with pip into the site-packages target. The sdist declares no
# runtime dependencies. pip verifies the build-dependency hashes against
# PyPI.
python3 -m pip install --no-cache-dir --no-deps --target %{buildroot}%{python3_sitelib} .

%files
%license LICENSE
%dir %{python3_sitelib}/webencodings/
%{python3_sitelib}/webencodings/*
%{python3_sitelib}/webencodings-0.5.1.dist-info/

%changelog
* Thu Sep 17 2026 Team Chaotix <chaotix@metallinux.dev> - 0.5.1-1.el10
- Source build as a runtime dependency of python3-tinycss2, needed by the
  Cinnamon settings theme panel (TASK-0017); version matches the Fedora 44
  reference
