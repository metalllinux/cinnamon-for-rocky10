#!/usr/bin/env bash
# gdm-drive.sh — shared GDM greeter driver library (runs INSIDE the VM).
#
# Part of the TASK-0008 login harness. Sourced by in-VM scripts; never
# executed directly. Used by:
#   - vm-test/test-gdm-login.sh (libvirt reproduction harness, item 2)
#   - tasks/*/task.bash (Sparky/Sparrow matrix, item 9a/9b)
#
# Design note (item 2, verified 2026-08-24; re-verified live in the
# test VM 2026-08-27, item 2c): Rocky Linux 10 cannot run an X11 GDM
# greeter, so this library drives the Wayland one:
#   - no xorg-x11-server-Xorg exists in the EL10 repos. Item 2c
#     evidence (Rocky 10.2 guest with baseos/appstream/crb/extras +
#     the local repo): `dnf list available "xorg-x11-server*"` lists
#     only xorg-x11-server-Xwayland-devel (crb); `dnf provides
#     /usr/bin/Xorg` -> "No matches found"; on a Rocky 10.2 host with
#     EPEL 10 enabled, `dnf list available xorg-x11-server-Xorg` ->
#     "No matching Packages". The X11-forced greeter + XTest/xdotool
#     design (plan, VM reproduction design; risk R1) is infeasible;
#   - gdm-47 on EL10 ships only /usr/libexec/gdm-wayland-session (no
#     gdm-x-session) — `rpm -ql gdm | grep /usr/libexec/` shows
#     gdm-auth-config-redhat, gdm-new-session, gdm-runtime-config,
#     gdm-session-worker, gdm-wayland-session — so GDM itself is
#     Wayland-only.
# The greeter is mutter on Wayland. This library drives it with:
#   - ukey (uinput): kernel-level keyboard + relative mouse,
#     display-server agnostic (tasks/lib/ukey.c);
#   - gdm-a11y.py (AT-SPI2): greeter UI state, session-list contents,
#     node geometry for clicks, evidence (tasks/lib/gdm-a11y.py).
# Both build inputs (gcc, kernel-headers, python3-dbus) are in the
# EL10 default repos. Pixel evidence is captured host-side with
# `virsh screenshot` (the VNC framebuffer), not in-VM.
#
# The test user's password is generated inside the VM at baseline and
# never leaves it (planning doc, VM reproduction design).

# --- Guard: must be sourced, not executed ---
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "gdm-drive.sh must be sourced, not executed." >&2
    exit 1
fi

# --- Constants ---

# Harness files live here inside the VM (scp'd by the orchestrator).
GDM_HARNESS_DIR="${GDM_HARNESS_DIR:-/root/gdm-harness}"
# Evidence lands here inside the VM; the orchestrator scp's it back.
EVIDENCE_DIR="${EVIDENCE_DIR:-/root/evidence}"
# Plan "Login drive": wait up to 120s for the login to complete.
GDM_LOGIN_WAIT="${GDM_LOGIN_WAIT:-120}"
# Poll interval for greeter/session waits.
GDM_POLL="${GDM_POLL:-3}"
# Settle time after the greeter session registers, for the UI to come
# up and grab keyboard focus before the first typed character.
GDM_GREETER_SETTLE="${GDM_GREETER_SETTLE:-10}"

UKEY="${GDM_HARNESS_DIR}/ukey"
A11Y="python3 ${GDM_HARNESS_DIR}/gdm-a11y.py"

# --- Driver build ---

# Build the ukey uinput driver inside the VM. Idempotent.
gdm_build_driver() {
    if [ -x "$UKEY" ]; then
        echo "gdm-drive: ukey already built" >&2
        return 0
    fi
    [ -f "${GDM_HARNESS_DIR}/ukey.c" ] || {
        echo "gdm-drive: ${GDM_HARNESS_DIR}/ukey.c missing (scp it first)" >&2
        return 1
    }
    # Build inputs, all EL10 default repos: gcc (appstream),
    # kernel-headers (appstream, for linux/uinput.h), python3-dbus
    # (baseos, for gdm-a11y.py).
    dnf install -y gcc kernel-headers python3-dbus || return 1
    modprobe uinput 2>/dev/null || true
    [ -e /dev/uinput ] || {
        echo "gdm-drive: /dev/uinput missing (uinput module not loadable)" >&2
        return 1
    }
    gcc -O2 -Wall -Wextra -o "$UKEY" "${GDM_HARNESS_DIR}/ukey.c" || {
        echo "gdm-drive: ukey build failed" >&2
        return 1
    }
    echo "gdm-drive: ukey built at $UKEY" >&2
    return 0
}

# --- logind session state ---

# `loginctl list-sessions --no-legend` columns on EL10 (systemd 257),
# verified in the item 2 observation pass — do not guess the indices:
#   $1 SESSION  $2 UID  $3 USER  $4 SEAT  $5 LEADER  $6 CLASS
#   $7 TTY  $8 IDLE  $9 SINCE
# CLASS is "greeter" for the GDM greeter session, "user" for user
# logins. The x11/wayland TYPE is per-session, from
# `loginctl show-session <id> -p Type`.
gdm_session_of() {  # user -> first session id (may be empty)
    loginctl list-sessions --no-legend 2>/dev/null \
        | awk -v u="$1" '$3 == u { print $1; exit }'
}

gdm_greeter_session_id() {  # the GDM greeter session id (may be empty)
    loginctl list-sessions --no-legend 2>/dev/null \
        | awk '$3 == "gdm" && $6 == "greeter" { print $1; exit }'
}

gdm_session_type() {  # session id -> TYPE (may be empty)
    [ -n "$1" ] || return 1
    loginctl show-session "$1" -p Type 2>/dev/null | cut -d= -f2
}

gdm_session_state() {  # session id -> STATE (may be empty)
    [ -n "$1" ] || return 1
    loginctl show-session "$1" -p State 2>/dev/null | cut -d= -f2
}

# True when the GDM greeter session is registered with logind. The
# greeter session persists across user logouts (GDM wayland
# architecture: one compositor for the seat).
gdm_greeter_up() {
    [ -n "$(gdm_greeter_session_id)" ]
}

# Wait for the greeter session, then settle for the UI to come up.
gdm_wait_greeter() {
    local timeout="${1:-90}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if gdm_greeter_up; then
            echo "gdm-drive: greeter session up after ${elapsed}s; settling ${GDM_GREETER_SETTLE}s" >&2
            sleep "$GDM_GREETER_SETTLE"
            return 0
        fi
        sleep "$GDM_POLL"
        elapsed=$((elapsed + GDM_POLL))
    done
    echo "gdm-drive: greeter session not ready after ${timeout}s" >&2
    return 1
}

# Greeter UI readiness: the a11y bus answers and a login surface is
# visible. Two greeter modes (item 2, attempt 4, observed on the
# gdm-47 Wayland greeter):
#   - face list: known users shown as clickable faces; "Not listed?"
#     button present; there is NO "Log In" node in this mode (verified
#     by full a11y tree dump, 2026-08-25);
#   - username dialog: no listed users (or after "Not listed?"); a
#     "Log In" button is present.
# Ready when either marker is visible. $1 optional explicit needle,
# $2 optional timeout.
gdm_greeter_ui_ready() {
    local needle="${1:-}"
    local timeout="${2:-60}"
    local n
    if [ -n "$needle" ]; then
        n="$needle"
    else
        # Probe the face-list marker first (the common mode when any
        # user exists); fall back to the username-dialog marker.
        if $A11Y waitvis "Not listed?" 5 >/dev/null 2>&1; then
            n="Not listed?"
        else
            n="Log In"
        fi
    fi
    if $A11Y waitvis "$n" "$timeout" >/dev/null 2>&1; then
        return 0
    fi
    echo "gdm-drive: greeter a11y UI not ready ('${n}' not visible after ${timeout}s)" >&2
    return 1
}

# Ensure the greeter is (or becomes) the active login surface. If a
# test-user session from a previous run is still up, terminate it so
# the greeter returns. This makes --keep-vm re-runs idempotent.
# $1 optional user (default gdmtest).
gdm_ensure_greeter() {
    local user="${1:-gdmtest}"
    local timeout="${2:-150}"
    local sid
    if [ -n "$(gdm_session_of "$user")" ]; then
        echo "gdm-drive: terminating leftover ${user} session to reach the greeter" >&2
        loginctl terminate-user "$user" 2>/dev/null || true
        # Wait for the user session to actually go away before
        # expecting the greeter UI to return.
        local waited=0
        while [ -n "$(gdm_session_of "$user")" ] && [ "$waited" -lt 30 ]; do
            sleep 2
            waited=$((waited + 2))
        done
    fi
    gdm_wait_greeter "$timeout" || return 1
    gdm_greeter_ui_ready "" 90
}

# Wait for the greeter login surface (face list or username dialog)
# to return after a logout.
gdm_wait_greeter_ui() {
    local timeout="${1:-90}"
    gdm_greeter_ui_ready "" "$timeout" || {
        echo "gdm-drive: greeter login surface did not return after ${timeout}s" >&2
        return 1
    }
}

# --- a11y access (greeter UI state) ---

# Raw passthrough: gdm_a11y <tree|text|has|wait|find> [args...]
gdm_a11y() { $A11Y "$@"; }

# --- Input (via ukey/uinput) ---

gdm_type() { "$UKEY" type "$1"; }

gdm_key() { "$UKEY" key "$1"; }

gdm_combo() { "$UKEY" combo "$@"; }

gdm_move() { "$UKEY" move "$1" "$2"; }

gdm_click() { "$UKEY" click; }

# Absolute pointer placement: one ukey absmove with the absolute
# pointer axis (EV_ABS). Deterministic; no reading of the current
# position and no accumulation of relative deltas. (The earlier
# "move -10000 -10000 to clamp to 0,0" trick is wrong: the compositor
# does not clamp the logical pointer position, so relative deltas
# accumulate across invocations and the pointer drifts off-screen,
# where clicks land outside the display. Verified 2026-08-27, item 2c:
# no cursor drawn and face-list button clicks ignored until the
# absolute axis was added to ukey.)
gdm_abs_move() {
    "$UKEY" absmove "$1" "$2"
    sleep 0.3
}

gdm_abs_click() {
    gdm_abs_move "$1" "$2"
    gdm_click
    sleep 1
}

# Wait until the named node is visible, then click the center of its
# extents. $1 node name, $2 optional timeout. Returns 1 when the node
# never became visible.
gdm_click_visible() {
    local name="$1" timeout="${2:-30}"
    local line x y w h
    line=$($A11Y waitvis "$name" "$timeout" 2>/dev/null) || return 1
    x=$(cut -f3 <<<"$line")
    y=$(cut -f4 <<<"$line")
    w=$(cut -f5 <<<"$line")
    h=$(cut -f6 <<<"$line")
    if [ "$w" != "-" ] && [ "$h" != "-" ]; then
        gdm_abs_click $((x + w / 2)) $((y + h / 2))
        echo "gdm-drive: clicked visible node '${name}' at $((x + w / 2)),$((y + h / 2))" >&2
        return 0
    fi
    echo "gdm-drive: visible node '${name}' has no usable extents: ${line}" >&2
    return 1
}

# --- Session selection ---

# Map the harness session shorthand to the greeter's session entry
# name (the .desktop Name= value the Login Options menu lists).
# Anything not listed here selects no session (the greeter's default,
# GNOME).
gdm_session_entry() {
    case "$1" in
        cinnamon) echo "Cinnamon" ;;
        cinnamon-wayland) echo "Cinnamon (Wayland)" ;;
        *) echo "" ;;
    esac
}

# The greeter shows a "Caps lock is on" warning label while caps lock
# is set. The ukey device is created fresh per invocation (its
# modifier state always starts off), so the typed password is
# unaffected; the warning is display hygiene for the evidence capture
# (a stray "Caps lock is on" in the failure-dialog a11y dump is a
# surprise to read). Toggle until the label is gone, 3 tries max.
gdm_caps_lock_off() {
    local i
    for i in 1 2 3; do
        $A11Y waitvis "Caps lock is on" 2 >/dev/null 2>&1 || return 0
        gdm_key Caps_Lock
        sleep 1
    done
    return 0
}

# Select session $1 in the GDM greeter session selector. $1 is the
# greeter's session entry name (e.g. "Cinnamon (Wayland)").
#
# Sequence (item 2c-2, pinned by the live gdm-47 Wayland greeter
# a11y tree, 2026-08-27): the Wayland greeter has no Ctrl+Alt+Down
# session shortcut (that is X11 GDM behavior; the gdm-47 Wayland
# greeter is gnome-shell). The selector is the "Login Options" menu
# button in the bottom-right corner. Its a11y [menu] node is hidden
# (INT_MIN extents) in the face-list stage and gains on-screen
# extents once the password stage is up. The menu lists a "Password"
# item and a "Session Type" item; the available session entries sit
# under the latter, so "Session Type" is expanded first when the
# target entry is not directly visible.
#   1. Click the visible "Login Options" menu button.
#   2. If the target entry is not visible, click "Session Type".
#   3. Click the target entry at its screen-space extents center.
# Returns 0 when the entry was found and clicked, 1 when the
# "Login Options" button is not visible or the entry is not in the
# menu (the caller decides how to proceed).
gdm_select_session() {
    local session="$1"
    gdm_click_visible "Login Options" 15 || {
        echo "gdm-drive: 'Login Options' menu button not visible (is the password stage up?)" >&2
        return 1
    }
    sleep 1
    if ! $A11Y waitvis "$session" 5 >/dev/null 2>&1; then
        gdm_click_visible "Session Type" 10 || true
        sleep 1
    fi
    if gdm_click_visible "$session" 15; then
        sleep 1
        return 0
    fi
    echo "gdm-drive: session entry '${session}' not found in the Login Options menu" >&2
    return 1
}

# Dismiss a lingering login-failure dialog (if any) so a fresh attempt
# starts at the username field. Escape closes the greeter error
# dialog; a no-op when no dialog is up.
gdm_dismiss_errors() {
    gdm_key Escape 2>/dev/null || true
    sleep 1
}

# --- Login drive ---

# Full login drive.
#   $1 user, $2 passfile (in-VM, 0600), $3 session: "cinnamon"
#   selects the Cinnamon entry, "cinnamon-wayland" the Cinnamon
#   (Wayland) entry; anything else logs in to the default (GNOME)
#   session.
#
# Flow (item 2, attempt 4 face-list observation + item 2c-2 session
# menu, pinned by a11y-tree evidence on the gdm-47 Wayland greeter):
#   1. The greeter shows the face list when the user is known (there
#      is no username field and no "Log In" node in this mode), so
#      the password dialog is reached by clicking the user's face.
#   2. Fallback: "Not listed?" opens the username+password dialog;
#      type the username, Return (the documented GDM username-advance
#      key).
#   3. Wait for the password entry (a11y role "password text" becomes
#      visible) before typing the password. (On the gdm-47 Wayland
#      greeter the "Login code:" label stays hidden in the password
#      stage — item 2c-2 — so the role, not the label, is the
#      readiness marker.)
#   4. Session selection (the Login Options menu) is only offered
#      from the login dialog, so it happens after step 3, before the
#      password. When a session is explicitly requested and cannot be
#      selected, the attempt aborts (return 2) without submitting
#      credentials: logging in to the default session would test a
#      different thing and blur the verdict.
# Returns: 0 input sent, 2 requested session not selectable,
# 3 greeter not reachable / no login surface.
gdm_login() {
    local user="$1" passfile="$2" session="$3"
    local entry

    [ -r "$passfile" ] || {
        echo "gdm-drive: cannot read passfile ${passfile}" >&2
        return 3
    }
    gdm_ensure_greeter "$user" 150 || return 3
    gdm_dismiss_errors

    # Reach the password dialog.
    if gdm_click_visible "$user" 20; then
        : # face clicked; GDM advances to the password field
    else
        gdm_click_visible "Not listed?" 20 || return 3
        gdm_type "$user"
        sleep 1
        gdm_key Return
    fi
    $A11Y waitvisrole "password text" 30 >/dev/null 2>&1 || {
        echo "gdm-drive: password entry did not appear after user selection" >&2
        return 3
    }
    sleep 1

    entry=$(gdm_session_entry "$session")
    if [ -n "$entry" ]; then
        gdm_select_session "$entry" || {
            echo "gdm-drive: requested session '${entry}' not selectable; aborting without credentials" >&2
            return 2
        }
        sleep 1
    fi

    gdm_caps_lock_off
    gdm_type "$(cat "$passfile")"
    sleep 1
    gdm_key Return
    return 0
}

# State-based verdict (plan, Login drive step 4): a logind session of
# type x11/wayland for the user plus the expected desktop process.
#   $1 user, $2 timeout, $3.. expected desktop process names
#   (matched against the full command line with pgrep -f).
# Returns: 0 verified, 3 no session appeared, 4 a session registered
# but no expected desktop process.
gdm_wait_session() {
    local user="$1" timeout="$2"
    shift 2
    local elapsed=0 sid stype sstate p
    local last_state=""

    while [ "$elapsed" -lt "$timeout" ]; do
        sid=$(gdm_session_of "$user")
        if [ -n "$sid" ]; then
            stype=$(gdm_session_type "$sid")
            sstate=$(gdm_session_state "$sid")
            if [ "$stype" = "x11" ] || [ "$stype" = "wayland" ]; then
                for p in "$@"; do
                    if pgrep -u "$user" -f "$p" >/dev/null 2>&1; then
                        echo "gdm-drive: VERIFIED session ${sid} type=${stype} state=${sstate} proc='${p}'" >&2
                        return 0
                    fi
                done
                last_state="session ${sid} type=${stype} state=${sstate} but none of: $*"
            fi
        fi
        sleep "$GDM_POLL"
        elapsed=$((elapsed + GDM_POLL))
    done

    echo "gdm-drive: no verified session for ${user} after ${timeout}s; last: ${last_state:-none}" >&2
    if [ -n "$(gdm_session_of "$user")" ]; then
        return 4
    fi
    return 3
}

# Convenience: login + verdict in one call.
#   $1 user, $2 passfile, $3 session (cinnamon|other), $4.. procs
gdm_login_and_verify() {
    local user="$1" passfile="$2" session="$3"
    shift 3
    gdm_login "$user" "$passfile" "$session" || true
    gdm_wait_session "$user" "$GDM_LOGIN_WAIT" "$@"
}

# --- Evidence (plan, Login drive step 5; always captured) ---

# Capture the plan's evidence set for a login attempt.
#   $1 tag (directory name), $2 since-timestamp (date '+%F %T'), $3 user
# Pixel evidence (screenshots) is host-side: `virsh screenshot`.
gdm_capture_evidence() {
    local tag="$1" t0="$2" user="$3"
    local dir="${EVIDENCE_DIR}/${tag}"
    local uid sid
    mkdir -p "$dir"

    # GDM's view of the attempt (journal, DoD evidence box).
    journalctl -u gdm --since "$t0" --no-pager > "${dir}/journal-gdm.log" 2>&1 || true
    # The session-launch view for the test user (plan step 5).
    uid=$(id -u "$user" 2>/dev/null || true)
    if [ -n "$uid" ]; then
        journalctl "_UID=${uid}" --since "$t0" --no-pager > "${dir}/journal-uid.log" 2>&1 || true
    fi
    # PAM view (DoD evidence box; the service tag proves A3).
    tail -n 200 /var/log/secure > "${dir}/secure-tail.log" 2>/dev/null || true
    # Session state.
    loginctl list-sessions --no-legend > "${dir}/loginctl-sessions.log" 2>&1 || true
    sid=$(gdm_session_of "$user")
    if [ -n "$sid" ]; then
        loginctl show-session "$sid" > "${dir}/loginctl-session-${sid}.log" 2>&1 || true
    fi
    getenforce > "${dir}/getenforce.log" 2>&1 || true
    # Session entries visible to the greeter at this moment.
    ls -l /usr/share/xsessions/ /usr/share/wayland-sessions/ \
        > "${dir}/sessions-available.log" 2>&1 || true
    # Greeter UI state via AT-SPI2 (the Wayland-era replacement for
    # xwininfo/xwd): structure, node geometry, dialog wording.
    $A11Y tree > "${dir}/a11y-tree.log" 2>&1 || true
    $A11Y text > "${dir}/a11y-text.log" 2>&1 || true
    echo "gdm-drive: evidence for '${tag}' in ${dir}" >&2
    return 0
}
