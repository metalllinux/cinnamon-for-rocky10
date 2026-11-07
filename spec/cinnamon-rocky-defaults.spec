Name:           cinnamon-rocky-defaults
Version:        1.0
Release:        9.el10
Summary:        Rocky Linux 10 branding defaults for the Cinnamon desktop

License:        GPLv2+
URL:            https://github.com/metalllinux/cinnamon-for-rocky10
BuildArch:      noarch

# The package ships five small original config files written inline in the
# install section below; the spec is the single source of truth for them
# (house rule .gitignore keeps source tarballs out of git, and this package
# has no upstream tarball to fetch). Source0 is the GPLv2 license text,
# byte-identical to this repository's top-level LICENSE (the project it
# ships defaults for is GPL-2.0 upstream).
Source0:        GPLv2.txt
# sha256: 8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643

# The scriptlets run `dconf update` and `glib-compile-schemas`, so the tools
# must exist at install time. The wallpaper file and the icon theme entry are
# referenced by the overrides and must be present. The five schema files named
# by the overrides must exist so glib-compile-schemas succeeds
# (org.cinnamon from cinnamon, org/cinnamon/desktop/background and
# org.cinnamon.desktop.interface from cinnamon-desktop, org.nemo.desktop and
# org.nemo.preferences from nemo, the last two in the same schema file). The Mint-Y-Aqua icon theme named by the interface override
# must be installed (mint-y-icons). The Mint-X styles file needs its
# gtk themes (mint-themes), its icon themes (mint-x-icons), and the
# cursor it names (mint-cursor-themes); the Mint-L styles file shipped by
# mint-l-theme needs the same plus mint-l-icons.
Requires:       dconf
Requires:       gdm
Requires:       glib2
Requires:       lightdm
Requires:       cinnamon
Requires:       cinnamon-desktop
Requires:       mint-cursor-themes
Requires:       mint-l-icons
Requires:       mint-l-theme
Requires:       mint-themes
Requires:       mint-x-icons
Requires:       mint-y-icons
Requires:       nemo
Requires:       rocky-backgrounds
Requires:       rocky-logos
Requires:       slick-greeter
Requires:       slick-greeter-cinnamon

%description
Rocky Linux 10 first-login branding for the Cinnamon desktop. Ships a dconf
system override that sets the wallpaper to the Gemstone Skies day/night pair,
a gschema override that matches the F45 Cinnamon baseline's panel branding
(menu button icon name and label, panel height, the 14-item applet set
including show-desktop and nightlight, the System Info logo, and the
Mint-Y-Aqua icon theme that renders the baseline's taskbar and desktop
icon art), and a gschema override that defaults the nemo desktop icon
visibility (computer/home/trash) to true so the desktop shows Computer,
Home, and Rubbish Bin like the baseline, and a gschema override that
defaults org.nemo.preferences treat-root-as-normal to true so
nemo-desktop runs on the root-only fresh consumer (nemo refuses to run
nemo-desktop as root unless that key is set; upstream documents the key
exactly for this case, "For some systems there is only a root user").
The wallpaper file comes from
rocky-backgrounds; the menu button icon name resolves to the
fedora-logo-sprite pixmaps entry installed by rocky-logos (Rocky logo
art). The icon theme comes from mint-y-icons. This package redistributes
no logo or icon theme bytes of its own. The dconf override applies to all
users until a user changes the wallpaper in Cinnamon Settings (the user db
wins in the dconf profile chain). The desktop-icon and branding overrides
are schema defaults; a user who changes a setting in Cinnamon Settings wins
in the dconf profile chain. The Mint-X styles file (10_mint-x.styles) makes
the 11 Mint-X window-button theme colour variants selectable in the
Cinnamon Themes panel's simplified view, derived from the Mint-X block of
Fedora's 22_fedora.styles (the F45 Cinnamon baseline's styles file) with
the cursor changed from Paper to Bibata-Modern-Classic, the cursor the
Rocky 10 build packages via mint-cursor-themes (TASK-0038 window-button
theme availability). On fresh install the package also makes lightdm the
default display manager (lightdm.service enabled, gdm.service disabled
when its unit file is present, default target graphical.target); GDM
stays installed and switching back is documented in INSTALL.md.

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
# at install time; 10_ prefix sorts before 99_ defaults. The [org.cinnamon]
# keys mirror the icon-scope keys of Fedora's own
# 10_cinnamon-common.gschema.override (owned by the F45 cinnamon package),
# which is a distro artifact our upstream-tarball build does not carry;
# the [org.cinnamon.desktop.interface] key selects the icon theme that
# renders the taskbar/desktop icons (the schema comes from
# cinnamon-desktop). See the 1.0-4 changelog and TASK-0038.
install -d %{buildroot}%{_datadir}/glib-2.0/schemas
cat > %{buildroot}%{_datadir}/glib-2.0/schemas/10_cinnamon_rocky_branding.gschema.override <<'EOF'
[org.cinnamon]
enabled-applets=['panel1:left:0:menu@cinnamon.org', 'panel1:left:1:show-desktop@cinnamon.org', 'panel1:left:2:grouped-window-list@cinnamon.org', 'panel1:right:0:keyboard@cinnamon.org', 'panel1:right:1:systray@cinnamon.org', 'panel1:right:2:xapp-status@cinnamon.org', 'panel1:right:3:notifications@cinnamon.org', 'panel1:right:4:printers@cinnamon.org', 'panel1:right:5:removable-drives@cinnamon.org', 'panel1:right:6:network@cinnamon.org', 'panel1:right:7:nightlight@cinnamon.org', 'panel1:right:8:power@cinnamon.org', 'panel1:right:9:calendar@cinnamon.org', 'panel1:right:10:sound@cinnamon.org']
app-menu-icon-name='fedora-logo-sprite'
app-menu-label='Menu'
system-icon='fedora-logo-sprite'
panels-height=['1:32']
[org.cinnamon.desktop.interface]
icon-theme='Mint-Y-Aqua'
EOF

# gschema override. The nemo schema ships the three desktop icon keys
# defaulting to false on every release we track (6.7.4 and 6.7.5 alike);
# the F45 baseline shows the icons because Fedora's nemo package carries
# the same override (nemo-fedora.gschema.override). Mirror it so a fresh
# consumer's desktop matches the baseline (TASK-0038).
cat > %{buildroot}%{_datadir}/glib-2.0/schemas/10_cinnamon_rocky_desktop-icons.gschema.override <<'EOF'
[org.nemo.desktop]
computer-icon-visible=true
home-icon-visible=true
trash-icon-visible=true
EOF

# gschema override. nemo-desktop refuses to start when its effective user
# id is 0 unless org.nemo.preferences treat-root-as-normal is true (the
# refusal is upstream nemo behaviour, nemo-desktop-application.c, and the
# man page documents the key for root-only systems). A fresh consumer of
# this set is root-only, so without the key nemo-desktop can never start
# and the desktop icons from the override above can never appear, no
# matter what the icon keys say. Default the key to true for this
# distribution's root-only consumer; the key only takes effect for a root
# session, non-root users are unaffected, and a user who changes it in
# Cinnamon Settings wins in the dconf profile chain. (TASK-0038
# fresh-consumer desktop-icons FAIL.)
cat > %{buildroot}%{_datadir}/glib-2.0/schemas/10_cinnamon_rocky_nemo-root.gschema.override <<'EOF'
[org.nemo.preferences]
treat-root-as-normal=true
EOF

# Cinnamon Themes panel styles file (simplified view). Derived from the
# Mint-X block of Fedora's 22_fedora.styles (the F45 Cinnamon baseline's
# styles.d, Source3 of the F45 cinnamon package): same 11 colour variants,
# same colours, same "themes" mapping to the Mint-X gtk-3.0 themes, one
# change - the cursor is Bibata-Modern-Classic instead of Paper, because
# Paper is not packaged for Rocky 10 while Bibata-Modern-Classic comes
# from mint-cursor-themes. The Mint-X family has no -Dark themes upstream,
# so the style is light-only, as in the Fedora block. The 10_ prefix
# sorts after mint-l-theme's upstream 00_mint-l.styles. (TASK-0038
# window-button theme availability.)
install -d %{buildroot}%{_datadir}/cinnamon/styles.d
cat > %{buildroot}%{_datadir}/cinnamon/styles.d/10_mint-x.styles <<'EOF'
{
  "styles": [
    {
      "name": "Mint-X",
      "light": [
          {"name": "blue", "color": "#5b73c4", "themes": "Mint-X-Blue", "cursor": "Bibata-Modern-Classic"},
          {"name": "aqua", "color": "#6cabcd", "themes": "Mint-X-Aqua", "cursor": "Bibata-Modern-Classic"},
          {"name": "teal", "color": "#5aaa9a", "themes": "Mint-X-Teal", "cursor": "Bibata-Modern-Classic"},
          {"name": "green", "color": "#9ab87c", "themes": "Mint-X", "cursor": "Bibata-Modern-Classic", "default": "true"},
          {"name": "sand", "color": "#c8ac69", "themes": "Mint-X-Sand", "cursor": "Bibata-Modern-Classic"},
          {"name": "brown", "color": "#aa876a", "themes": "Mint-X-Brown", "cursor": "Bibata-Modern-Classic"},
          {"name": "grey", "color": "#9d9d9d", "themes": "Mint-X-Grey", "cursor": "Bibata-Modern-Classic"},
          {"name": "orange", "color": "#db9d61", "themes": "Mint-X-Orange", "cursor": "Bibata-Modern-Classic"},
          {"name": "red", "color": "#c15b58", "themes": "Mint-X-Red", "cursor": "Bibata-Modern-Classic"},
          {"name": "pink", "color": "#c76199", "themes": "Mint-X-Pink", "cursor": "Bibata-Modern-Classic"},
          {"name": "purple", "color": "#8c6ec9", "themes": "Mint-X-Purple", "cursor": "Bibata-Modern-Classic"}
        ]
    }
  ]
}
EOF

# DM switch order matters: gdm.service and lightdm.service both carry
# [Install] Alias=display-manager.service, the same alias path, and
# systemctl enable fails over an alias another unit already holds while
# systemctl disable only removes the alias when it points at that unit.
# So on fresh install (gdm self-enables, then this %post runs) the gdm
# alias must go first, or the lightdm enable fails over it and the
# disable removes it, leaving both display managers disabled.
%post
set -e
if [ $1 -eq 1 ]
then
if [ -f /usr/lib/systemd/system/gdm.service ]
then
systemctl disable gdm.service
fi
systemctl enable lightdm.service
systemctl set-default graphical.target
fi
dconf update
glib-compile-schemas %{_datadir}/glib-2.0/schemas

# Removal reverses the default (the documented-option direction): drop the
# lightdm enable, then restore the gdm enable if its unit file is present,
# so the machine always boots to a working graphical login. set -e keeps a
# failed systemctl visible in the dnf log instead of a silent state.
%postun
set -e
if [ $1 -eq 0 ]
then
systemctl disable lightdm.service
if [ -f /usr/lib/systemd/system/gdm.service ]
then
systemctl enable gdm.service
fi
fi
dconf update
glib-compile-schemas %{_datadir}/glib-2.0/schemas

%files
%license %{_datadir}/licenses/%{name}/LICENSE
%{_sysconfdir}/dconf/db/local.d/10_cinnamon_rocky_wallpaper
%{_datadir}/glib-2.0/schemas/10_cinnamon_rocky_branding.gschema.override
%{_datadir}/glib-2.0/schemas/10_cinnamon_rocky_desktop-icons.gschema.override
%{_datadir}/glib-2.0/schemas/10_cinnamon_rocky_nemo-root.gschema.override
%{_datadir}/cinnamon/styles.d/10_mint-x.styles

%changelog
* Thu Nov 05 2026 Team Chaotix <chaotix@metallinux.dev> - 1.0-9.el10
- Ship a gschema override defaulting org.nemo.preferences
  treat-root-as-normal to true. nemo-desktop refuses to start with an
  effective uid of 0 unless that key is true, and a fresh consumer of
  this set is root-only, so the desktop icons from the 1.0-3 override
  could never appear on a fresh consumer (the key is inert for
  non-root users; upstream documents it for root-only systems).
  TASK-0038 fresh-consumer desktop-icons FAIL.

* Wed Nov 04 2026 Team Chaotix <chaotix@metallinux.dev> - 1.0-8.el10
- Fix the %post DM order: disable gdm.service before enabling lightdm.
  Both units share the display-manager.service alias, and systemctl
  enable fails over an alias gdm already holds (verified on the test VM),
  so the 1.0-7 order left both display managers disabled whenever gdm
  held the default, which is the fresh-consumer state (gdm self-enables
  before this %post runs, and the spec Requires gdm). The 1.0-7 %postun
  order (disable lightdm, then enable gdm) was already correct and is
  unchanged. Add set -e to both scriptlets so a failed systemctl surfaces
  as a scriptlet failure in the dnf log instead of a silently wrong DM
  state (TASK-0038, Shadow 2026-11-03 blocker).

* Tue Nov 03 2026 Team Chaotix <chaotix@metallinux.dev> - 1.0-7.el10
- Fix the %post and %postun scriptlets, which failed at parse time in
  1.0-6 (every if missing its then), so the lightdm default was not set
  by the package: add the then to all three if bodies, and add the
  guarded systemctl enable gdm.service to %postun so removal restores
  the GDM login (TASK-0038, Shadow 2026-11-03 blocker).

* Tue Nov 03 2026 Team Chaotix <chaotix@metallinux.dev> - 1.0-6.el10
- Make lightdm the default display manager for fresh consumers: add
  Requires on gdm, lightdm, slick-greeter, and slick-greeter-cinnamon
  (GDM stays installed as a documented option), and on fresh install
  enable lightdm.service, disable gdm.service if its unit file is
  present, and set the default target to graphical.target; removal
  reverses the lightdm enable (TASK-0038 X server and lightdm port).

* Mon Nov 02 2026 Team Chaotix <chaotix@metallinux.dev> - 1.0-5.el10
- Ship the Mint-X styles file (10_mint-x.styles, project-authored, derived
  from the Mint-X block of Fedora's 22_fedora.styles with the cursor
  changed from Paper to Bibata-Modern-Classic) so the 11 Mint-X
  window-button theme colour variants are selectable in the Cinnamon
  Themes panel's simplified view, and add Requires on the theme family
  packages (mint-l-theme, mint-l-icons, mint-x-icons, mint-themes,
  mint-cursor-themes) so the Mint-L and Mint-X styles resolve their gtk,
  icon, cinnamon, and cursor parts (TASK-0038 window-button theme
  availability).

* Sat Nov 01 2026 Team Chaotix <chaotix@metallinux.dev> - 1.0-4.el10
- Match the F45 Cinnamon baseline's panel branding (icon scope only):
  14-item enabled-applets (adds show-desktop and nightlight, drops
  separator, favorites, cornerbar), app-menu-icon-name='fedora-logo-sprite'
  and system-icon='fedora-logo-sprite' (same key values as the baseline;
  on Rocky the name resolves to the rocky-logos Rocky-logo art),
  app-menu-label='Menu', panels-height=['1:32'], and
  icon-theme='Mint-Y-Aqua' (org.cinnamon.desktop.interface) so the
  taskbar and desktop icons render the baseline's Mint-Y art. The
  baseline's non-icon override keys (sounds, screensaver fonts, cursor,
  fonts, gtk-theme, button-layout, workspaces, indicators) are not set:
  their themes and fonts are not installed on Rocky (TASK-0038 icon
  parity). Requires: mint-y-icons added.

* Fri Oct 30 2026 Team Chaotix <chaotix@metallinux.dev> - 1.0-3.el10
- Ship a gschema override that defaults computer/home/trash icon
  visibility to true so a fresh consumer shows Computer/Home/Rubbish Bin
  on the desktop, matching the F45 Cinnamon baseline. The nemo schema
  itself ships the keys defaulting to false (6.7.4 and 6.7.5 alike);
  the reference desktop gets the icons from the same override in
  Fedora's nemo package (nemo-fedora.gschema.override) (TASK-0038)

* Fri Sep 18 2026 Team Chaotix <chaotix@metallinux.dev> - 1.0-2.el10
- Ship the GPLv2 license text (Source0, byte-identical to the repository's
  top-level LICENSE) (Omega TASK-0017)

* Tue Sep 15 2026 Team Chaotix <chaotix@metallinux.dev> - 1.0-1
- Initial package: wallpaper dconf system override and branding gschema
  override for the Cinnamon desktop on Rocky Linux 10
