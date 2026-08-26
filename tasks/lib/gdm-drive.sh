#!/usr/bin/env bash
# gdm-drive.sh — shared GDM greeter driver library (runs INSIDE the VM).
#
# Part of the TASK-0008 login harness. Sourced by in-VM scripts; never
# executed directly. Used by:
#   - vm-test/test-gdm-login.sh (libvirt reproduction harness, item 2)
#   - tasks/*/task.bash (Sparky/Sparrow matrix, item 9a/9b)
#
# Design note (item 2, verified 2026-08-24): Rocky Linux 10 cannot run
# an X11 GDM greeter, so this library drives the Wayland one:
#   - no xorg-x11-server-Xorg exists in the EL10 repos
#     (appstream/baseos/crb, EPEL 10) or on the 10.2 DVD (only
#     xorg-x11-server-Xwayland, no runtime), so no X server is
#     installable and the plan's X11-forced greeter + XTest/xdotool
#     design (plan, VM reproduction design; risk R1) is infeasible;
#   - gdm-47 on EL10 ships only /usr/libexec/gdm-wayland-session (no
#     gdm-x-session), so GDM itself is Wayland-only.
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

# Absolute pointer placement without reading the current position:
# push the pointer off the top-left corner (the compositor clamps it
# to 0,0), then walk back to (x,y).
gdm_abs_move() {
    gdm_move -10000 -10000
    sleep 0.3
    gdm_move "$1" "$2"
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

# Select session $1 in the GDM greeter session selector.
#
# Sequence (item 2 observation pass, pinned by a11y-tree + VNC
# screenshot evidence):
#   1. Ctrl+Alt+Down opens the session selector (GDM greeter
#      shortcut, documented GDM behavior).
#   2. The entry is found in the greeter's a11y tree by name ("Cinnamon"
#      exact match preferred over substrings such as "Cinnamon
#      (Wayland)") and clicked at its screen-space extents center via
#      ukey.
# Returns 0 when the entry was found and clicked, 1 when it was not
# found in the a11y tree (the caller decides how to proceed; the
# greeter then logs in with whatever the selector currently holds).
gdm_select_session() {
    local session="$1"
    local line x y w h
    gdm_combo ctrl alt Down
    sleep 2
    if line=$($A11Y find "$session" 2>/dev/null); then
        x=$(cut -f3 <<<"$line")
        y=$(cut -f4 <<<"$line")
        w=$(cut -f5 <<<"$line")
        h=$(cut -f6 <<<"$line")
        if [ "$w" != "-" ] && [ "$h" != "-" ]; then
            gdm_abs_click $((x + w / 2)) $((y + h / 2))
            echo "gdm-drive: clicked session entry '${session}' at $((x + w / 2)),$((y + h / 2))" >&2
            sleep 1
            return 0
        fi
    fi
    echo "gdm-drive: session entry '${session}' not found in greeter a11y tree" >&2
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
#   $1 user, $2 passfile (in-VM, 0600), $3 session: "cinnamon" selects
#   the Cinnamon entry; anything else logs in to the default (GNOME)
#   session.
#
# Flow (item 2, attempt 4, pinned by a11y-tree observation on the
# gdm-47 Wayland greeter):
#   1. The greeter shows the face list when the user is known (there
#      is no username field and no "Log In" node in this mode), so
#      the password dialog is reached by clicking the user's face.
#   2. Fallback: "Not listed?" opens the username+password dialog;
#      type the username, Return (the documented GDM username-advance
#      key).
#   3. Wait for the password field ("Login code:" label becomes
#      visible) before typing the password.
#   4. Session selection (Ctrl+Alt+Down) is only offered from the
#      login dialog, so it happens after step 3, before the password.
# Returns: 0 input sent, 3 greeter not reachable / no login surface.
gdm_login() {
    local user="$1" passfile="$2" session="$3"

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
    $A11Y waitvis "Login code:" 30 >/dev/null 2>&1 || {
        echo "gdm-drive: password field did not appear after user selection" >&2
        return 3
    }
    sleep 1

    if [ "$session" = "cinnamon" ]; then
        gdm_select_session "Cinnamon" || {
            echo "gdm-drive: continuing without a selected Cinnamon entry (default session will be used)" >&2
        }
        sleep 1
    fi

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
