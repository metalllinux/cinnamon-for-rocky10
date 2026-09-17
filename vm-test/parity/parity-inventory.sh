#!/usr/bin/env bash
# parity-inventory.sh — TASK-0017 item 0.2, read-only Cinnamon desktop inventory.
#
# Collects structured evidence for every row of the TASK-0017 parity
# checklist (panel applets, themes, extension/applet/desklet manager,
# screensaver, Cinnamon Settings, main menu, nemo, terminal,
# session/power controls, wallpaper, branding) from a Cinnamon VM.
#
# Read-only by construction: no gsettings set, no dconf writes, no
# package operations, no config edits. It only reads packages, schemas,
# files, and process state. The one thing it refuses to do is take
# screenshots itself: on these VMs (virtio-vga, Wayland) the in-VM
# capture tools are unreliable, so the host-side orchestrator opens the
# relevant app and captures with `virsh screenshot <domain> <file>`
# (the method proven in item 2.1). Screenshot rows are emitted here as
# STAGED markers naming the app to open.
#
# Usage: parity-inventory.sh <output-dir> <label>
#   <output-dir>  directory to receive inventory-<label>.txt (created if absent)
#   <label>       short tag, e.g. rocky10-2.2 or fedora-ref-0.3
#
# Runs as root (preferred; it finds the seat0 graphical session user and
# re-runs user-scoped queries with runuser) or as the session user.
# Works on both Cinnamon 6.7 (Rocky 10) and 6.6.7 (Fedora 44 ref): every
# 6.6/6.7-divergent fact is probed defensively and reported, not assumed.
set -u

OUTDIR="${1:-}"
LABEL="${2:-}"
if [ -z "$OUTDIR" ] || [ -z "$LABEL" ]; then
    echo "usage: $0 <output-dir> <label>" >&2
    exit 2
fi
mkdir -p "$OUTDIR"
REPORT="$OUTDIR/inventory-$LABEL.txt"
: > "$REPORT"

# --- session user discovery -------------------------------------------------
# The seat0 graphical session user is the one whose desktop we inventory.
# loginctl list-sessions --no-legend columns (systemd 257, verified in the
# gdm-drive.sh harness): $1 SESSION $2 UID $3 USER $4 SEAT $5 LEADER
# $6 CLASS $7 TTY $8 IDLE $9 SINCE. CLASS is "user" for real logins.
SESSION_USER=""
if [ "$(id -u)" = "0" ]; then
    SESSION_USER="$(loginctl list-sessions --no-legend 2>/dev/null \
        | awk '$4 ~ /seat/ && $6 == "user" {print $3; exit}')"
fi
if [ -z "$SESSION_USER" ]; then
    SESSION_USER="$(whoami)"
fi
SESSION_UID="$(id -u "$SESSION_USER" 2>/dev/null || echo '')"

# ucmd: run a command in the session user's dconf environment.
# gsettings/dconf need XDG_RUNTIME_DIR; as root the user's runtime dir is
# /run/user/<uid>. When we are already the session user, run directly.
ucmd() {
    if [ "$(id -u)" = "0" ] && [ "$(id -u)" != "$SESSION_UID" ]; then
        runuser -u "$SESSION_USER" -- env XDG_RUNTIME_DIR="/run/user/$SESSION_UID" "$@" 2>/dev/null
    else
        env XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" "$@" 2>/dev/null
    fi
}

emit()  { printf '%s\n' "$@" >> "$REPORT"; }
sect()  { emit ""; emit "### $1"; }
key()   { emit "KEY: $1"; }
block() { emit "$1" >> "$REPORT"; }   # preformatted multiline block

# --- 1. OS / VM identity -----------------------------------------------------
sect "OS-VM"
key "PRETTY_NAME: $(. /etc/os-release && echo "$PRETTY_NAME")"
key "HOSTNAME: $(hostname)"
key "KERNEL: $(uname -r)"
key "INVENTORY_USER: $SESSION_USER (uid $SESSION_UID)"
key "UPTIME: $(uptime -p 2>/dev/null || uptime)"

# --- 2. Cinnamon stack versions ----------------------------------------------
sect "STACK"
key "CINNEMON_STACK:"
block "$(rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null \
    | grep -iE '^(cinnamon|cjs|mozjs|muffin|nemo|xapps|gtk-layer-shell|gdk-pixbuf)' \
    | sort | sed 's/^/    /')"
if command -v cinnamon >/dev/null 2>&1; then
    key "CINNAMON_VERSION: $(cinnamon --version 2>/dev/null | head -1)"
fi
if command -v nemo >/dev/null 2>&1; then
    key "NEMO_VERSION: $(ucmd nemo --version 2>/dev/null | head -1 || nemo --version 2>/dev/null | head -1)"
fi

# --- 3. Live session ----------------------------------------------------------
sect "SESSION"
# Note: root's own ssh session carries XDG_SESSION_TYPE=tty, so it must
# not be used as the primary source when inventorying another user.
SID="$(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$SESSION_USER" '$3==u && $4 ~ /seat/ && $6 == "user" {print $1; exit}')"
key "SESSION_ID: ${SID:-none}"
if [ -n "$SID" ]; then
    key "SESSION_TYPE: $(loginctl show-session "$SID" --value -p Type 2>/dev/null)"
else
    key "SESSION_TYPE: ${XDG_SESSION_TYPE:-none}"
fi
key "GDMSESSION: ${GDMSESSION:-n/a (no session env in this shell)}"
key "SESSION_PROCESSES:"
block "$(ps -eo user,comm 2>/dev/null | grep -E 'cinnamon|muffin|nemo-desktop|gnome-shell|gdm-wayland' | grep -v grep | sed 's/^/    /' | sort -u)"
key "SCREENSHOT_STAGED: 01-session (full desktop: wallpaper + panel + menu button branding; host captures via virsh)"

# --- 4. Panel applets ----------------------------------------------------------
sect "APPLETS"
key "ENABLED_APPLETS:"
block "$(ucmd gsettings get org.cinnamon enabled-applets 2>/dev/null | sed 's/^/    /' || emit '    (org.cinnamon schema absent)')"
key "PANELS_ENABLED: $(ucmd gsettings get org.cinnamon panels-enabled 2>/dev/null)"
key "AVAILABLE_APPLET_DIRS: $(ls -d /usr/share/cinnamon/applets/*/ 2>/dev/null | wc -l)"
key "AVAILABLE_APPLETS:"
block "$(ls /usr/share/cinnamon/applets/ 2>/dev/null | sed 's/^/    /')"
key "SCREENSHOT_STAGED: 02-panel (bottom panel with applet icons; host captures via virsh)"

# --- 5. Branding (menu button) --------------------------------------------------
sect "BRANDING"
key "APP_MENU_ICON_NAME: $(ucmd gsettings get org.cinnamon app-menu-icon-name 2>/dev/null)"
key "SYSTEM_ICON: $(ucmd gsettings get org.cinnamon system-icon 2>/dev/null)"
ICON_NAME="$(ucmd gsettings get org.cinnamon app-menu-icon-name 2>/dev/null | tr -d "'")"
if [ -n "$ICON_NAME" ]; then
    ICON_FILE="$(find /usr/share/icons /usr/share/pixmaps -name "$ICON_NAME.*" 2>/dev/null | head -3)"
    key "ICON_FILES: ${ICON_FILE:-NOT FOUND in icon themes or pixmaps}"
    if [ -n "$ICON_FILE" ]; then
        key "ICON_OWNER: $(rpm -qf "$(echo "$ICON_FILE" | head -1)" 2>/dev/null || echo 'not rpm-owned')"
    fi
fi
key "SCREENSHOT_STAGED: 03-menu-button (bottom-left of panel; included in 01-session)"

# --- 6. Wallpaper ----------------------------------------------------------------
sect "WALLPAPER"
key "PICTURE_URI: $(ucmd gsettings get org.cinnamon.desktop.background picture-uri 2>/dev/null)"
key "PICTURE_OPTIONS: $(ucmd gsettings get org.cinnamon.desktop.background picture-options 2>/dev/null)"
key "PRIMARY_COLOR: $(ucmd gsettings get org.cinnamon.desktop.background primary-color 2>/dev/null)"
key "ROCKY_BACKGROUND_FILES:"
block "$(ls /usr/share/backgrounds/ 2>/dev/null | grep -iE 'rocky|gemstone' | sed 's/^/    /' || echo '    none')"
WP="$(ucmd gsettings get org.cinnamon.desktop.background picture-uri 2>/dev/null | tr -d "'" | sed 's|^file://||')"
if [ -n "$WP" ] && [ -f "$WP" ]; then
    key "WALLPAPER_OWNER: $(rpm -qf "$WP" 2>/dev/null || echo 'not rpm-owned')"
else
    key "WALLPAPER_OWNER: (uri not a readable file: $WP)"
fi
key "SCREENSHOT_STAGED: 04-wallpaper (desktop region of 01-session; host analyzes non-black fraction)"

# --- 7. Themes ---------------------------------------------------------------------
sect "THEMES"
key "CINNEMON_THEME_NAME: $(ucmd gsettings get org.cinnamon.theme name 2>/dev/null)"
key "GTK_THEME: $(ucmd gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null)"
key "ICON_THEME: $(ucmd gsettings get org.cinnamon.desktop.interface icon-theme 2>/dev/null)"
key "SHELL_THEME_ASSETS: $(ls /usr/share/cinnamon/theme/ 2>/dev/null | wc -l) files under /usr/share/cinnamon/theme/"
key "USER_THEMES: $(ls "$HOME/.themes" "$HOME/.local/share/themes" 2>/dev/null | grep -v ':' | sed 's/^/    /' || echo '    none')"
key "SCREENSHOT_STAGED: 05-themes-panel (Cinnamon Settings > Themes; host captures via virsh)"

# --- 8. Extension / applet / desklet manager ------------------------------------------
sect "EXTENSION_MANAGER"
key "EXTENSIONS_DIR: $(ls -d /usr/share/cinnamon/extensions 2>/dev/null || echo 'absent (no shipped extensions on this system)')"
key "SHIPPED_EXTENSIONS:"
block "$(ls /usr/share/cinnamon/extensions/ 2>/dev/null | sed 's/^/    /' || echo '    none')"
key "DESKLET_DIRS: $(ls -d /usr/share/cinnamon/desklets/*/ 2>/dev/null | wc -l)"
key "MANAGER_PANEL_DESKTOPS:"
block "$(ls /usr/share/applications/cinnamon-settings-{applets,desklets,extensions}.desktop 2>/dev/null | sed 's/^/    /')"
key "MANAGER_MODULE: $(ls /usr/share/cinnamon/cinnamon-settings/modules/cs_extensions.py 2>/dev/null || echo 'absent')"
key "SCREENSHOT_STAGED: 06-extension-manager (cinnamon-settings extensions open; host captures via virsh)"

# --- 9. Screensaver ---------------------------------------------------------------------
sect "SCREENSAVER"
key "CINNAMON_SCREENSAVER_PKG: $(rpm -q cinnamon-screensaver 2>/dev/null || echo 'not installed (folded into cinnamon shell at 6.7)')"
key "SCREENSAVER_COMMAND: $(command -v cinnamon-screensaver-command 2>/dev/null || echo 'absent')"
key "SCREENSAVER_VERSION: $(cinnamon-screensaver-command --version 2>/dev/null || echo 'n/a')"
key "SCREENSAVER_SERVICE: $(systemctl is-active cinnamon-screensaver 2>/dev/null || echo 'no service (6.7 renders the shield in-shell via js/ui/screensaver)')"
key "SHELL_SCREENSAVER_CODE: $(ls -d /usr/share/cinnamon/js/ui/screensaver 2>/dev/null || echo 'absent')"
key "SCREENSAVER_MODE: $(ucmd gsettings get org.cinnamon.desktop.screensaver mode 2>/dev/null || echo 'schema absent')"
key "SCREENSAVER_LOCK_ENABLED: $(ucmd gsettings get org.cinnamon.desktop.screensaver lock-enabled 2>/dev/null || echo 'schema absent')"

# --- 10. Main menu + Cinnamon Settings menu ----------------------------------------------
sect "MENU"
key "MENU_APPLET_DIR: $(ls -d /usr/share/cinnamon/applets/menu@cinnamon.org 2>/dev/null || echo 'absent')"
key "MENU_APPLET_ENABLED: $(ucmd gsettings get org.cinnamon enabled-applets 2>/dev/null | grep -c 'menu@cinnamon.org')"
key "CINNAMON_SETTINGS_MENU_ENTRY: $(ls /usr/share/applications/cinnamon-settings-default.desktop 2>/dev/null || echo 'absent')"
key "SETTINGS_PANEL_COUNT: $(ls /usr/share/applications/cinnamon-settings-*.desktop 2>/dev/null | wc -l)"
key "SETTINGS_PANELS:"
block "$(ls /usr/share/applications/cinnamon-settings-*.desktop 2>/dev/null | xargs -r -n1 basename 2>/dev/null | sed 's/^/    /')"
key "SCREENSHOT_STAGED: 07-main-menu (main menu open with Cinnamon Settings submenu; host captures via virsh)"

# --- 11. nemo ------------------------------------------------------------------------------
sect "NEMO"
key "NEMO_PKG: $(rpm -q nemo 2>/dev/null || echo 'not installed')"
key "NEMO_DESKTOP: $(ps -eo comm 2>/dev/null | grep -c '^nemo-desktop$')"
key "NEMO_BINARY: $(command -v nemo 2>/dev/null || echo 'absent')"
key "SCREENSHOT_STAGED: 08-nemo (nemo file manager open; host captures via virsh)"

# --- 12. Terminal ------------------------------------------------------------------------------
sect "TERMINAL"
key "GNOME_TERMINAL: $(command -v gnome-terminal 2>/dev/null || echo 'absent')"
if command -v gnome-terminal >/dev/null 2>&1; then
    key "GNOME_TERMINAL_VERSION: $(gnome-terminal --version 2>/dev/null || echo 'n/a (needs display)')"
    key "TERM_OWNER: $(rpm -qf "$(command -v gnome-terminal)" 2>/dev/null || echo 'not rpm-owned')"
fi
key "ALTERNATIVES: $(command -v konsole xterm 2>/dev/null | sed 's/^/    /' || echo '    none')"
key "SCREENSHOT_STAGED: 09-terminal (terminal open; host captures via virsh, or records absence)"

# --- 13. Session / power controls ------------------------------------------------------------
sect "SESSION_POWER"
key "POWER_APPLET_ENABLED: $(ucmd gsettings get org.cinnamon enabled-applets 2>/dev/null | grep -c 'power@cinnamon.org')"
key "POWER_SETTINGS_PANEL: $(ls /usr/share/applications/cinnamon-settings-power.desktop 2>/dev/null || echo 'absent')"
key "SESSION_SETTINGS_PANEL: $(ls /usr/share/applications/cinnamon-settings-sessions.desktop 2>/dev/null || echo 'absent (6.7 session controls)')"
key "SESSION_SCHEMA_IDLE: $(ucmd gsettings get org.cinnamon.desktop.session idle-delay 2>/dev/null || ucmd gsettings get org.gnome.desktop.session idle-delay 2>/dev/null || echo 'absent')"
key "WAYLAND_SESSIONS: $(ls /usr/share/wayland-sessions/ 2>/dev/null | sed 's/^/    /')"
key "X_SESSIONS: $(ls /usr/share/xsessions/ 2>/dev/null | sed 's/^/    /')"
key "SCREENSHOT_STAGED: 10-power-menu (panel power applet menu open; host captures via virsh)"
key "SCREENSHOT_STAGED: 11-session-controls (Cinnamon Settings session/power panel; host captures via virsh)"

# --- 14. dconf background effective values --------------------------------------------------------
sect "DCONF_BACKGROUND"
for k in picture-uri picture-options primary-color secondary-color color-shading-type; do
    key "org.cinnamon.desktop.background $k: $(ucmd gsettings get org.cinnamon.desktop.background "$k" 2>/dev/null || echo 'key absent')"
done

emit ""
emit "### END (label=$LABEL, $(date -u +%Y-%m-%dT%H:%M:%SZ))"

cat "$REPORT"
echo ""
echo "inventory written: $REPORT"
