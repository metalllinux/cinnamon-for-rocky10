#!/usr/bin/env python3
"""gdm-a11y.py — AT-SPI2 state reader for the GDM greeter (in-VM, root).

Part of the TASK-0008 login harness (planning doc
TASK-0008-cinnamon-gdm-auth-fix.md, work breakdown item 2).

Why this exists: the GDM greeter on Rocky Linux 10 runs on Wayland
(mutter). There is no X server to inspect (no xorg-x11-server-Xorg in
the EL10 repos, gdm-47 is Wayland-only), so the greeter's accessibility
tree over the a11y D-Bus socket is the in-VM source of UI state:
waits, session-list contents, node geometry for ukey(1) clicks, and
evidence (failure-dialog wording per plan A4). Input is sent by
ukey(1) (uinput); this tool never sends input.

The greeter's tree lives on the gdm user's a11y bus, not the caller's:
the connection target is derived from the gdm user's uid at run time.

Dependencies: python3-dbus (EL10 baseos).

Usage:
  gdm-a11y.py tree [max-depth]     dump role/name/extents/state per node
  gdm-a11y.py text                 all non-empty node names, one per line
  gdm-a11y.py has <substring>      exit 0 when a node name contains it
  gdm-a11y.py wait <substring> [timeout]
                                   poll (1 s) until a node name contains
                                   <substring>; exit 0 found, 1 timeout
  gdm-a11y.py find <name>          first node whose name equals <name>,
                                   else first that contains it. Prints
                                   one tab-separated line:
                                   role<TAB>name<TAB>x<TAB>y<TAB>
                                   width<TAB>height<TAB>focused
                                   ("-" for missing extents), exit 0;
                                   exit 1 when no node matches.
  gdm-a11y.py waitvis <name> [timeout]
                                   poll (1 s) until a node whose name
                                   matches <name> (exact preferred) is
                                   VISIBLE (on-screen extents, all >= 0).
                                   Hidden dialogs stay in the tree with
                                   INT_MIN extents; this is how to tell
                                   a dialog is actually up. Prints the
                                   find-format line; exit 0 visible,
                                   1 timeout.
  gdm-a11y.py textof <name>        print the AT-SPI Text content of the
                                    first visible node whose name matches
                                    <name> (exact preferred). Reads what
                                    has been typed into a field (password
                                    fields read back empty by design).
                                    Exit 0 when a node was found, 1 when
                                    not.
   gdm-a11y.py findrole <role>      first node whose AT-SPI role name
                                     contains <role> (e.g. "password text"
                                     for the greeter's password entry,
                                     which has no node name). Visible
                                     nodes win over hidden ones. Prints
                                     the find-format line; exit 1 when
                                     no node matches.
   gdm-a11y.py waitvisrole <role> [timeout]
                                     poll (1 s) until a node whose role
                                     contains <role> is VISIBLE. Same
                                     semantics as waitvis, matched by
                                     role instead of name.
   gdm-a11y.py findrolex <role> [x] [y]
                                     like findrole, but the role name
                                     must EQUAL <role> exactly (the
                                     substring form reaches "password
                                     text" when looking for "text").
                                     With [x] [y], only visible nodes
                                     whose extents contain the point
                                     match, innermost (deepest) wins —
                                     point targeting for nodes that
                                     share a role with other nodes on
                                     the same stage. Same output and
                                     exit codes.
   gdm-a11y.py waitvisrolex <role> [timeout]
                                     like waitvisrole, exact role match.
   gdm-a11y.py textofext <x> <y>   print the AT-SPI Text content of the
                                     visible node at screen point (x, y):
                                     the innermost (deepest) visible
                                     node whose extents contain the
                                     point, no node name required
                                     (the greeter's editable entries
                                     carry empty names). Tries covering
                                     nodes from innermost outward until
                                     one exposes a Text interface.
                                     Exit 0 with the text (possibly
                                     empty), 1 when no visible node
                                     covers the point, 2 when no
                                     covering node exposes Text.
"""

import sys
import time

import dbus

A11Y_IFACE = "org.a11y.atspi.Accessible"
COMP_IFACE = "org.a11y.atspi.Component"
REGISTRY_NAME = "org.a11y.atspi.Registry"
REGISTRY_PATH = "/org/a11y/atspi/accessible/root"


def bus_address():
    import pwd

    try:
        uid = pwd.getpwnam("gdm").pw_uid
    except KeyError:
        sys.exit("gdm-a11y: no gdm user on this system")
    return f"unix:path=/run/user/{uid}/at-spi/bus"


def connect():
    try:
        return dbus.bus.BusConnection(bus_address())
    except Exception as e:
        sys.exit(f"gdm-a11y: cannot connect to a11y bus {bus_address()}: {e!r}")


def acc(bus, name, path):
    return dbus.Interface(bus.get_object(name, path), A11Y_IFACE)


def node_role(bus, name, path):
    try:
        return str(acc(bus, name, path).GetRoleName())
    except Exception:
        return "?"


def node_name(bus, name, path):
    try:
        p = dbus.Interface(
            bus.get_object(name, path), "org.freedesktop.DBus.Properties"
        )
        v = p.Get(A11Y_IFACE, "Name")
        return str(v)
    except Exception:
        return ""


def node_states(bus, name, path):
    try:
        a = acc(bus, name, path)
        return set(str(s) for s in a.GetStates())
    except Exception:
        return set()


# AtspiCoordType: 0 = invalid, 1 = SCREEN, 2 = WINDOW
ATSPI_COORD_SCREEN = 1


def node_extents(bus, name, path):
    """Screen-space (x, y, width, height) or None."""
    try:
        c = dbus.Interface(bus.get_object(name, path), COMP_IFACE)
        x, y, w, h = c.GetExtents(ATSPI_COORD_SCREEN)
        return (int(x), int(y), int(w), int(h))
    except Exception:
        return None


def extents_visible(ext):
    """True when extents are on-screen. Off-screen/hidden nodes report
    INT_MIN coordinates (mutter/AT-SPI convention), so a valid dialog
    is the one with all four values >= 0."""
    return ext is not None and all(v >= 0 for v in ext)


def walk(bus, name, path, depth=0, max_depth=16, out=None):
    """Collect (depth, role, name, states, extents, dbus_name,
    dbus_path) for the subtree. The D-Bus name/path are carried so
    commands can call interfaces (e.g. Text) on the matched node."""
    if out is None:
        out = []
    if depth > max_depth:
        return out
    try:
        a = acc(bus, name, path)
        role = str(a.GetRoleName())
    except Exception:
        out.append((depth, "<unreadable>", "", set(), None, name, path))
        return out
    nm = node_name(bus, name, path)
    states = node_states(bus, name, path)
    ext = node_extents(bus, name, path)
    out.append((depth, role, nm, states, ext, name, path))
    try:
        for child_name, child_path in a.GetChildren():
            walk(bus, str(child_name), str(child_path), depth + 1, max_depth, out)
    except Exception:
        pass
    return out


def greeter_nodes(bus):
    """Walk only the gnome-shell (greeter) application."""
    reg = acc(bus, REGISTRY_NAME, REGISTRY_PATH)
    nodes = []
    try:
        apps = reg.GetChildren()
    except Exception as e:
        sys.exit(f"gdm-a11y: cannot list a11y desktop: {e!r}")
    for app_name, app_path in apps:
        if node_role(bus, str(app_name), str(app_path)) != "application":
            continue
        if node_name(bus, str(app_name), str(app_path)) != "gnome-shell":
            continue
        walk(bus, str(app_name), str(app_path), 0, 16, nodes)
    return nodes


def match_node(bus, needle):
    """First greeter node whose name matches needle: exact match wins
    over substring; among matches a visible node wins over hidden
    duplicates (mutter keeps off-screen dialogs in the tree with
    INT_MIN extents). Returns the 7-tuple from walk() or None."""
    nodes = [n for n in greeter_nodes(bus) if n[2] == needle]
    if not nodes:
        nodes = [n for n in greeter_nodes(bus) if needle in n[2]]
    if not nodes:
        return None
    for n in nodes:
        if extents_visible(n[4]):
            return n
    return nodes[0]


def match_role(bus, needle):
    """First greeter node whose AT-SPI role name contains needle
    (e.g. 'password text'): some nodes carry no name at all (the
    greeter's password entry), so name matching cannot reach them.
    A visible node wins over hidden duplicates. Returns the 7-tuple
    from walk() or None."""
    nodes = [n for n in greeter_nodes(bus) if needle in n[1]]
    if not nodes:
        return None
    for n in nodes:
        if extents_visible(n[4]):
            return n
    return nodes[0]


def match_rolex(bus, needle, point=None):
    """First greeter node whose AT-SPI role name EQUALS needle exactly.
    The substring form (match_role) reaches 'password text' when
    looking for 'text', so exact matching is needed to single out the
    plain text nodes. With point=(x, y), only VISIBLE nodes whose
    extents contain the point match, and the innermost (deepest) wins:
    the point form is how to target a node that shares its role with
    other nodes on the same stage (the username dialog's entry is a
    role-'text' node, as are the face-list label texts). Without a
    point, a visible node wins over hidden duplicates. Returns the
    7-tuple from walk() or None."""
    if point is not None:
        px, py = point
        hits = []
        for n in greeter_nodes(bus):
            if n[1] != needle or not extents_visible(n[4]):
                continue
            x, y, w, h = n[4]
            if x <= px < x + w and y <= py < y + h:
                hits.append(n)
        if not hits:
            return None
        return max(hits, key=lambda n: n[0])
    nodes = [n for n in greeter_nodes(bus) if n[1] == needle]
    if not nodes:
        return None
    for n in nodes:
        if extents_visible(n[4]):
            return n
    return nodes[0]


def cmd_tree(args):
    max_depth = int(args[0]) if args else 16
    bus = connect()
    for depth, role, nm, states, ext, _name, _path in greeter_nodes(bus):
        line = f"{'  ' * depth}[{role}] {nm!r}"
        if ext is not None:
            x, y, w, h = ext
            line += f" @({x},{y} {w}x{h})"
        if "focused" in states:
            line += " FOCUSED"
        print(line)


def cmd_text(args):
    bus = connect()
    for _, role, nm, _, _, _name, _path in greeter_nodes(bus):
        if nm:
            print(nm)


def names_present(bus, needle):
    for _, _, nm, _, _, _name, _path in greeter_nodes(bus):
        if needle in nm:
            return True
    return False


def cmd_has(args):
    if not args:
        sys.exit("usage: gdm-a11y.py has <substring>")
    bus = connect()
    sys.exit(0 if names_present(bus, args[0]) else 1)


def cmd_wait(args):
    if not args:
        sys.exit("usage: gdm-a11y.py wait <substring> [timeout]")
    needle = args[0]
    timeout = int(args[1]) if len(args) > 1 else 60
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            bus = connect()
            if names_present(bus, needle):
                return
        except SystemExit:
            raise
        except Exception:
            pass
        time.sleep(1)
    sys.exit(1)


def fmt_line(node):
    """The find-format line for a walk() 7-tuple."""
    depth, role, nm, states, ext, _name, _path = node
    x, y, w, h = ext if ext is not None else ("-", "-", "-", "-")
    focused = "1" if "focused" in states else "0"
    return f"{role}\t{nm}\t{x}\t{y}\t{w}\t{h}\t{focused}"


def cmd_find(args):
    if not args:
        sys.exit("usage: gdm-a11y.py find <name>")
    bus = connect()
    n = match_node(bus, args[0])
    if n is None:
        sys.exit(1)
    print(fmt_line(n))


def cmd_findrole(args):
    if not args:
        sys.exit("usage: gdm-a11y.py findrole <role>")
    bus = connect()
    n = match_role(bus, args[0])
    if n is None:
        sys.exit(1)
    print(fmt_line(n))


def cmd_waitvis(args):
    if not args:
        sys.exit("usage: gdm-a11y.py waitvis <name> [timeout]")
    needle = args[0]
    timeout = int(args[1]) if len(args) > 1 else 60
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            bus = connect()
            n = match_node(bus, needle)
            if n is not None and extents_visible(n[4]):
                print(fmt_line(n))
                return
        except SystemExit:
            raise
        except Exception:
            pass
        time.sleep(1)
    sys.exit(1)


def cmd_waitvisrole(args):
    if not args:
        sys.exit("usage: gdm-a11y.py waitvisrole <role> [timeout]")
    needle = args[0]
    timeout = int(args[1]) if len(args) > 1 else 60
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            bus = connect()
            n = match_role(bus, needle)
            if n is not None and extents_visible(n[4]):
                print(fmt_line(n))
                return
        except SystemExit:
            raise
        except Exception:
            pass
        time.sleep(1)
    sys.exit(1)


def cmd_findrolex(args):
    if not args:
        sys.exit("usage: gdm-a11y.py findrolex <role> [x] [y]")
    point = None
    if len(args) >= 3:
        try:
            point = (int(args[1]), int(args[2]))
        except ValueError:
            sys.exit("usage: gdm-a11y.py findrolex <role> [x] [y]")
    bus = connect()
    n = match_rolex(bus, args[0], point)
    if n is None:
        sys.exit(1)
    print(fmt_line(n))


def cmd_waitvisrolex(args):
    if not args:
        sys.exit("usage: gdm-a11y.py waitvisrolex <role> [timeout]")
    needle = args[0]
    timeout = int(args[1]) if len(args) > 1 else 60
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            bus = connect()
            n = match_rolex(bus, needle)
            if n is not None and extents_visible(n[4]):
                print(fmt_line(n))
                return
        except SystemExit:
            raise
        except Exception:
            pass
        time.sleep(1)
    sys.exit(1)


def cmd_textof(args):
    if not args:
        sys.exit("usage: gdm-a11y.py textof <name>")
    bus = connect()
    n = match_node(bus, args[0])
    if n is None:
        sys.exit(1)
    _depth, _role, _nm, _states, _ext, dname, dpath = n
    try:
        t = dbus.Interface(bus.get_object(dname, dpath),
                           "org.a11y.atspi.Text")
        # GetText(firstChild, lastChild): the whole field.
        text = str(t.GetText(0, 2 ** 31 - 1))
    except Exception as e:
        print(f"gdm-a11y: textof: Text interface failed: {e!r}",
              file=sys.stderr)
        sys.exit(1)
    print(text)


def cmd_textofext(args):
    if len(args) < 2:
        sys.exit("usage: gdm-a11y.py textofext <x> <y>")
    try:
        px, py = int(args[0]), int(args[1])
    except ValueError:
        sys.exit("usage: gdm-a11y.py textofext <x> <y>")
    bus = connect()
    hits = []
    for depth, _role, _nm, _states, ext, dname, dpath in greeter_nodes(bus):
        if not extents_visible(ext):
            continue
        x, y, w, h = ext
        if x <= px < x + w and y <= py < y + h:
            hits.append((depth, dname, dpath))
    if not hits:
        sys.exit(1)
    # Innermost first: the text leaf is the deepest node covering the
    # point (its containers cover it too, but sit above it in the
    # tree). Containers rarely expose Text; the leaf does.
    hits.sort(key=lambda t: t[0], reverse=True)
    for _depth, dname, dpath in hits:
        try:
            t = dbus.Interface(bus.get_object(dname, dpath),
                               "org.a11y.atspi.Text")
            # GetText(firstChild, lastChild): the whole field.
            print(str(t.GetText(0, 2 ** 31 - 1)))
            return
        except Exception:
            continue
    print("gdm-a11y: textofext: no covering node exposes a Text "
          f"interface at ({px},{py})", file=sys.stderr)
    sys.exit(2)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    args = sys.argv[2:]
    if cmd == "tree":
        cmd_tree(args)
    elif cmd == "text":
        cmd_text(args)
    elif cmd == "has":
        cmd_has(args)
    elif cmd == "wait":
        cmd_wait(args)
    elif cmd == "find":
        cmd_find(args)
    elif cmd == "waitvis":
        cmd_waitvis(args)
    elif cmd == "findrole":
        cmd_findrole(args)
    elif cmd == "waitvisrole":
        cmd_waitvisrole(args)
    elif cmd == "findrolex":
        cmd_findrolex(args)
    elif cmd == "waitvisrolex":
        cmd_waitvisrolex(args)
    elif cmd == "waiteditable":
        cmd_waiteditable(args)
    elif cmd == "textof":
        cmd_textof(args)
    elif cmd == "textofext":
        cmd_textofext(args)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
