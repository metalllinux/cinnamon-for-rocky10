Name:           cinnamon-rocky-defaults
Version:        1.0
Release:        2.el10
Summary:        Rocky Linux 10 branding defaults for the Cinnamon desktop

License:        GPLv2+
URL:            https://github.com/metalllinux/cinnamon-for-rocky10
BuildArch:      noarch

# The package ships two small original config files written inline in the
# install section below; the spec is the single source of truth for them
# (house rule .gitignore keeps source tarballs out of git, and this package
# has no upstream tarball to fetch). Source0 is the GPLv2 license text,
# byte-identical to this repository's top-level LICENSE (the project it
# ships defaults for is GPL-2.0 upstream).
Source0:        GPLv2.txt
# sha256: 8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643

# The scriptlets run `dconf update` and `glib-compile-schemas`, so the tools
# must exist at install time. The wallpaper file and the icon theme entry are
# referenced by the overrides and must be present. The two schema files named
# by the overrides must exist so glib-compile-schemas succeeds.
Requires:       dconf
Requires:       glib2
Requires:       cinnamon
Requires:       cinnamon-desktop
Requires:       rocky-backgrounds
Requires:       rocky-logos

%description
Rocky Linux 10 first-login branding for the Cinnamon desktop. Ships a dconf
system override that sets the wallpaper to the Gemstone Skies day/night pair
and a gschema override that sets the Rocky logo for the menu button. The
wallpaper file comes from rocky-backgrounds; the icon is referenced from the
hicolor theme entry installed by rocky-logos. This package redistributes no
logo bytes. The dconf override applies to all users until a user changes the
wallpaper in Cinnamon Settings (the user db wins in the dconf profile chain).

%install
# License text (GPLv2, byte-identical to the repository's top-level
# LICENSE).
install -d %{buildroot}%{_datadir}/licenses/%{name}
install -m 0644 %{_sourcedir}/GPLv2.txt %{buildroot}%{_datadir}/licenses/%{name}/LICENSE

# dconf system keyfile. dconf 0.40 reads keyfiles flat from
# /etc/dconf/db/<db>.d/ (subdirectories are not scanned, only locks/ is
# special-cased), so the file goes directly in local.d/.
install -d %{buildroot}%{_sysconfdir}/dconf/db/local.d
cat > %{buildroot}%{_sysconfdir}/dconf/db/local.d/10_cinnamon_rocky_wallpaper <<'EOF'
[org/cinnamon/desktop/background]
picture-uri='file:///usr/share/backgrounds/rocky-default-10-gemstone-skies-time.xml'
EOF

# gschema override. Merged into the compiled catalog by glib-compile-schemas
# at install time; 10_ prefix sorts before 99_ defaults.
install -d %{buildroot}%{_datadir}/glib-2.0/schemas
cat > %{buildroot}%{_datadir}/glib-2.0/schemas/10_cinnamon_rocky_branding.gschema.override <<'EOF'
[org.cinnamon]
app-menu-icon-name='fedora-logo-icon'
system-icon='fedora-logo-icon'
EOF

%post
dconf update
glib-compile-schemas %{_datadir}/glib-2.0/schemas

%postun
dconf update
glib-compile-schemas %{_datadir}/glib-2.0/schemas

%files
%license %{_datadir}/licenses/%{name}/LICENSE
%{_sysconfdir}/dconf/db/local.d/10_cinnamon_rocky_wallpaper
%{_datadir}/glib-2.0/schemas/10_cinnamon_rocky_branding.gschema.override

%changelog
* Fri Sep 18 2026 Team Chaotix <chaotix@metallinux.dev> - 1.0-2.el10
- Ship the GPLv2 license text (Source0, byte-identical to the repository's
  top-level LICENSE) (Omega TASK-0017)

* Tue Sep 15 2026 Team Chaotix <chaotix@metallinux.dev> - 1.0-1
- Initial package: wallpaper dconf system override and branding gschema
  override for the Cinnamon desktop on Rocky Linux 10
