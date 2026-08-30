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

# Ensure the greeter's caps lock state is OFF before the password is
# typed.
#
# Do NOT drive this from the "Caps lock is on" label: on the gdm-47
# Wayland greeter that label is a STATIC display. Verified 2026-08-27
# (item 2c-2b, greeter session c2): two ukey Caps_Lock presses
# flipped the kernel's cross-device caps LED 0 -> 1 -> 0 while the
# label stayed visible the whole time, and the a11y clock node
# advanced in the same window (the a11y tree itself is live, so the
# label is not updating, not the tree). The old label-driven loop
# ("toggle until the label is gone, 3 tries max") therefore sent all
# 3 presses whenever the label was visible and, starting from caps
# OFF, ended with caps ON: the typed password's a-f hex chars went
# out as A-F and pam_unix rejected it (the 17:38 UTC attempt:
# "password check failed for user (gdmtest)", with the passfile
# crypt-verified against /etc/shadow in the same window). That is the
# reproduction of the greeter's "Sorry, password authentication didn't
# work" dialog.
#
# The trustworthy state is the kernel's: every caps press flips the
# caps LED on the AT keyboard (the input core synchronizes it across
# devices, verified by ukey presses flipping
# /sys/class/leds/input1::capslock/brightness), and mutter's seat
# caps state is initialized from the keyboard's LED state when the
# greeter opens the input and is flipped by each caps press that
# reaches it. Normalize from the LED: exactly one press iff the LED
# is on. The caller (gdm_login) reaches the password stage by a click
# first, so the input pipeline is proven live before this runs and
# LED and mutter state are in parity.
gdm_caps_lock_off() {
    # Superseded in gdm_login by gdm_caps_probe_normalize (item 2c-3):
    # the readback-verified compositor state is ground truth, and a
    # blind LED-driven toggle would act on the proxy, not the state.
    # Kept for callers that only have the LED.
    local led
    led=$(cat /sys/class/leds/*capslock*/brightness 2>/dev/null | head -1)
    led="${led:-0}"
    if [ "$led" = "1" ]; then
        gdm_key Caps_Lock
        sleep 1
        led=$(cat /sys/class/leds/*capslock*/brightness 2>/dev/null | head -1)
        echo "gdm-drive: caps LED was on; after one toggle led=${led:-?}" >&2
    else
        echo "gdm-drive: caps LED off; no toggle sent" >&2
    fi
    return 0
}

# Probe-typed caps normalization with readback verification (item 2c-3).
#
# Why the probe: the kernel caps LED (gdm_caps_lock_off) is a parity
# proxy only while every caps press reaches the compositor. The 2c-2
# open hypothesis was exactly that divergence: Attempt B ran with the
# LED off and no toggle sent, yet the password was still rejected.
# The compositor's caps state is not directly readable (the "Caps
# lock is on" label is a static display — 2c-2 item 3 — and the
# password entry reads back empty by design), so it is verified by
# behavior: type a lowercase probe into an editable field, read the
# text back over AT-SPI (gdm-a11y.py textofext), and compare case.
#
# Where the probe is typed: the password stage reached by a face click
# has NO editable username field — the username is a read-only label
# (live a11y tree, item 2c-3: the 2c-2 probe coordinate (555,335) is a
# [label] 'gdmtest' with an empty [text] child, not an entry). The
# editable username entry lives in the "Not listed?" username dialog,
# so the pre-pass drives that dialog. It is also the documented GDM
# username-advance path (gdm_login step 2) that the face click used
# to bypass, so no new greeter surface is introduced.
#
# Greeter quirks the targeting must ride out (all verified live,
# item 2c-3, gdm-47/gnome-shell 49.4 greeter at 1280x800):
#   - the a11y state sets come back EMPTY for every node, so the
#     entry cannot be selected by the editable state;
#   - the dialog's entry is a role-'text' node like the face-list
#     label texts, so it is targeted by POINT (the fixed dialog
#     layout: entry origin (489,465), point (491,475) is inside the
#     entry in every reported-extent state);
#   - the a11y bridge oscillates the entry's reported width between
#     the widget allocation (302x20) and the text-content width
#     (5x20), and the dialog has been observed reporting hidden
#     while open, so entry lookup and readback are retried;
#   - the lingering failure dialog ("Sorry, password...") is NOT
#     closed by Escape (3 presses, no effect) but IS closed by its
#     Cancel button (click verified: returned to the face list).
#
# Sequence: dismiss a lingering dialog (Cancel click) -> "Not listed?"
# -> wait for the 'Empty User' label (the fresh-dialog marker) ->
# resolve the entry at the point -> click it (focus) -> type the
# probe -> textofext readback at the entry center. Lowercase readback
# = compositor caps OFF, verified. Uppercase readback = caps ON: one
# Caps_Lock press, clear the probe, retype, re-read; max 3 toggles.
# A readback that is neither the probe nor its uppercase means the
# input pipeline or the a11y readback is broken and the attempt must
# not be interpreted. The probe is always cleared before return, then
# the username is typed and submitted (Return; a second Return is the
# fallback advance), leaving the password stage up with the password
# entry focused.
#
# Returns: 0 password stage reached with the compositor caps state
# verified lowercase by readback; 1 the username dialog, its entry,
# or the password stage did not appear; 2 the readback did not match
# the probe in either case; 3 the caps state would not normalize
# within 3 toggles.
gdm_caps_probe_normalize() {
    local user="$1"
    local probe="abc"   # letters only: caps changes every char's case
    local line x y w h cx cy readback upper tries=0 n i k
    local led

    # Dismiss a lingering dialog (failure or stale username): its
    # Cancel button is the reliable dismissal (see quirks above).
    # The face list itself has no Cancel button, so the loop is a
    # no-op when no dialog is up.
    for n in 1 2 3; do
        if $A11Y waitvis "Cancel" 4 >/dev/null 2>&1; then
            gdm_click_visible "Cancel" 5 || true
            sleep 1
        else
            break
        fi
    done

    gdm_click_visible "Not listed?" 20 || {
        echo "gdm-drive: caps probe: 'Not listed?' not visible (face-list stage up?)" >&2
        return 1
    }
    # The fresh username dialog (unlisted user, always empty) is
    # marked by the 'Empty User' label.
    if ! $A11Y waitvis "Empty User" 30 >/dev/null 2>&1; then
        echo "gdm-drive: caps probe: username dialog did not open ('Empty User' not visible after 30s)" >&2
        return 1
    fi

    # Resolve the entry: the visible role-'text' node covering the
    # fixed point (491,475) (see quirks). Retry: the extent
    # oscillation and the dialog's intermittent a11y visibility make
    # a single lookup unreliable.
    line=""
    for i in 1 2 3 4 5; do
        line=$($A11Y findrolex "text" 491 475 2>/dev/null) && break
        sleep 1
    done
    if [ -z "$line" ]; then
        echo "gdm-drive: caps probe: no role-'text' node covering (491,475) after 5 tries" >&2
        return 1
    fi
    x=$(cut -f3 <<<"$line"); y=$(cut -f4 <<<"$line")
    w=$(cut -f5 <<<"$line"); h=$(cut -f6 <<<"$line")
    if [ "$w" = "-" ] || [ "$h" = "-" ]; then
        echo "gdm-drive: caps probe: entry has no usable extents: ${line}" >&2
        return 1
    fi
    cx=$((x + w / 2)); cy=$((y + h / 2))
    echo "gdm-drive: caps probe: entry @(${x},${y} ${w}x${h}), typing at ${cx},${cy}" >&2

    gdm_abs_click "$cx" "$cy"
    gdm_type "$probe"
    sleep 0.5
    readback=""
    for i in 1 2 3; do
        if readback=$($A11Y textofext "$cx" "$cy" 2>/dev/null); then
            break
        fi
        sleep 1
    done
    echo "gdm-drive: caps probe: typed '${probe}', readback '${readback}'" >&2

    upper=$(echo "$probe" | tr 'a-z' 'A-Z')
    while [ "$readback" != "$probe" ]; do
        if [ "$readback" = "$upper" ]; then
            tries=$((tries + 1))
            if [ "$tries" -gt 3 ]; then
                echo "gdm-drive: caps probe: still uppercase after 3 Caps_Lock toggles; giving up" >&2
                return 3
            fi
            echo "gdm-drive: caps probe: uppercase readback; Caps_Lock toggle ${tries}/3" >&2
            gdm_key Caps_Lock
            sleep 1
            for i in 1 2 3; do gdm_key BackSpace; done
            sleep 0.3
            gdm_type "$probe"
            sleep 0.5
            readback=""
            for k in 1 2 3; do
                if readback=$($A11Y textofext "$cx" "$cy" 2>/dev/null); then
                    break
                fi
                sleep 1
            done
            echo "gdm-drive: caps probe: re-read '${readback}'" >&2
        else
            echo "gdm-drive: caps probe: readback '${readback}' is neither '${probe}' nor its uppercase; input or a11y readback broken" >&2
            return 2
        fi
    done
    echo "gdm-drive: caps probe: compositor caps verified LOWERCASE by readback (${tries} toggle(s))" >&2

    # Verified lowercase: clear the probe, type and submit the username.
    for i in 1 2 3; do gdm_key BackSpace; done
    sleep 0.3
    gdm_type "$user"
    sleep 0.5
    gdm_key Return
    sleep 2
    if ! $A11Y waitvisrole "password text" 20 >/dev/null 2>&1; then
        # Return is the documented advance key; a second press is the
        # fallback (the dialog's submit button is an unnamed icon).
        gdm_key Return
        if ! $A11Y waitvisrole "password text" 30 >/dev/null 2>&1; then
            echo "gdm-drive: caps probe: password stage did not appear after username submit" >&2
            return 1
        fi
    fi
    led=$(cat /sys/class/leds/*capslock*/brightness 2>/dev/null | head -1)
    echo "gdm-drive: caps probe: kernel caps LED now ${led:-?} (parity record only)" >&2
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
# Flow (item 2c-3; session menu pinned by a11y-tree evidence on the
# gdm-47 Wayland greeter, item 2c-2):
#   1. Caps pre-pass (gdm_caps_probe_normalize): reach the password
#      stage through the "Not listed?" username dialog, type a probe
#      into its editable entry, read it back over AT-SPI, and toggle
#      Caps_Lock until the readback is lowercase (max 3), then clear
#      the probe and submit the username. This verifies the
#      compositor's caps state — the thing that corrupts the password
#      — by readback, which the face-click path could not do (its
#      password stage has no editable field; the face-name node at
#      (555,335) is a read-only label, verified in the live tree,
#      item 2c-3). The face-click path is retired for that reason.
#   2. Wait for the password entry (a11y role "password text" becomes
#      visible) before typing the password. (On the gdm-47 Wayland
#      greeter the "Login code:" label stays hidden in the password
#      stage — item 2c-2 — so the role, not the label, is the
#      readiness marker.)
#   3. Session selection (the Login Options menu) is only offered
#      from the login dialog, so it happens after step 2, before the
#      password. When a session is explicitly requested and cannot be
#      selected, the attempt aborts (return 2) without submitting
#      credentials: logging in to the default session would test a
#      different thing and blur the verdict.
#   4. The kernel caps LED is logged (read-only) for the parity
#      record. No toggle is sent here: the pre-pass verified the
#      compositor state by readback, and the LED is only a proxy
#      (2c-2: the two can diverge — a blind toggle would act on the
#      proxy, not the verified state).
# Returns: 0 input sent (caps state verified lowercase by readback),
# 2 requested session not selectable, 3 greeter not reachable / no
# login surface, 4 caps pre-pass failed (input not verified: no
# credentials submitted).
gdm_login() {
    local user="$1" passfile="$2" session="$3"
    local entry led rc

    [ -r "$passfile" ] || {
        echo "gdm-drive: cannot read passfile ${passfile}" >&2
        return 3
    }
    gdm_ensure_greeter "$user" 150 || return 3
    gdm_dismiss_errors

    gdm_caps_probe_normalize "$user" || {
        rc=$?
        echo "gdm-drive: caps pre-pass failed (rc=${rc}); aborting without credentials" >&2
        return 4
    }
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

    led=$(cat /sys/class/leds/*capslock*/brightness 2>/dev/null | head -1)
    echo "gdm-drive: pre-password kernel caps LED ${led:-?} (compositor caps verified lowercase by probe readback)" >&2
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
#
# Shadow finding 8 (TASK-0008): a non-zero gdm_login rc is
# propagated immediately instead of waiting GDM_LOGIN_WAIT. rc 2
# (requested session not selectable), 3 (no login surface) and 4
# (caps pre-pass failed) all mean the credentials were deliberately
# NOT submitted, so a 120s session wait would only turn a
# no-credentials abort into "no verified session after 120s" — the
# failed-login misdiagnosis of 2c-2. Returns: gdm_login's rc (2/3/4)
# on abort, otherwise gdm_wait_session's (0 verified, 3 no session
# appeared, 4 session without the expected process).
gdm_login_and_verify() {
    local user="$1" passfile="$2" session="$3"
    shift 3
    local rc=0
    gdm_login "$user" "$passfile" "$session" || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "gdm-drive: gdm_login rc=${rc}: credentials not submitted; not waiting for a session" >&2
        return "$rc"
    fi
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
