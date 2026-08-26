/* ukey.c — uinput virtual keyboard + mouse for the GDM login harness
 * (in-VM, root).
 *
 * Part of the TASK-0008 login harness (planning doc
 * TASK-0008-cinnamon-gdm-auth-fix.md, work breakdown item 2).
 *
 * Why this exists: the GDM greeter on Rocky Linux 10 runs on Wayland
 * (mutter), and no X server can be installed at all on EL10 — there is
 * no xorg-x11-server-Xorg in the EL10 repos (appstream/baseos/crb,
 * EPEL 10) or on the 10.2 DVD, and gdm-47 ships only
 * /usr/libexec/gdm-wayland-session (no gdm-x-session). An XTest driver
 * (xdotool or otherwise) therefore has no X server to talk to.
 * Kernel-level synthetic input via /dev/uinput is display-server
 * agnostic: mutter (greeter and GNOME session) and any future session
 * all consume it through the normal input stack. It is test-only,
 * built inside the VM, and is never shipped in the
 * cinnamon-for-rocky10 package set (no binary is ever committed).
 *
 * Build (inside the VM, as root):
 *   gcc -O2 -Wall -Wextra -o ukey ukey.c
 *
 * Dependencies: kernel-headers (linux/input.h, linux/uinput.h; EL10
 * appstream). /dev/uinput must exist (modprobe uinput if absent).
 *
 * Usage:
 *   ukey type <string>            type printable ASCII (40 ms/char)
 *   ukey key <name>               one key (names below)
 *   ukey combo <mod>... <name>    modifier combo, e.g.
 *                                 ukey combo ctrl alt Down
 *   ukey move <dx> <dy>           relative pointer motion
 *   ukey click                    left button press+release at the
 *                                 current pointer position
 *
 * Absolute pointer placement without reading the current position:
 *   ukey move -10000 -10000   (clamps the pointer to 0,0)
 *   ukey move <x> <y>         (now lands exactly on x,y)
 *   ukey click
 *
 * Key names: Return Enter Tab BackSpace Escape Caps_Lock space Down Up
 *            Left Right Home End Page_Up Page_Down F1..F12 a-z 0-9 and
 *            printable ASCII symbols (typed via type).
 *
 * A throwaway uinput device "gdm-harness" is created for each
 * invocation and destroyed on exit.
 *
 * Exit codes: 0 ok, 2 usage error, 3 device error.
 */

#include <linux/input.h>
#include <linux/uinput.h>

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define PRESS_HOLD_US 25000  /* between key press and release         */
#define CHAR_DELAY_US 40000  /* between typed characters              */
#define MOD_HOLD_US   30000  /* between modifiers and target key      */
#define MOTION_US     10000  /* between motion events                 */
/* Hotplug settle: udev/libinput need time to register a fresh uinput
 * device; events emitted (or the device destroyed) before the hotplug
 * is processed are lost. Observed on EL10 in the item 2 observation
 * pass: 100 ms device lifetime -> zero events delivered; 300 ms
 * settle -> events land. */
#define CREATE_SETTLE_US 300000  /* after UI_DEV_CREATE, before events */
#define DESTROY_HOLD_US  250000  /* after last event, before destroy   */

static void die(const char *msg)
{
    fprintf(stderr, "ukey: %s\n", msg);
    exit(2);
}

static void usage(void)
{
    fprintf(stderr,
        "usage: ukey type <string>\n"
        "       ukey key <name>\n"
        "       ukey combo <mod>... <name>   (mods: ctrl alt shift)\n"
        "       ukey move <dx> <dy>\n"
        "       ukey click\n");
    exit(2);
}

/* --- Key name table --- */

static const struct {
    const char *name;
    int code;
} key_names[] = {
    { "BackSpace",  KEY_BACKSPACE },
    { "Page_Up",    KEY_PAGEUP },
    { "Page_Down",  KEY_PAGEDOWN },
    { "Return",     KEY_ENTER },
    { "Enter",      KEY_ENTER },
    { "Escape",     KEY_ESC },
    { "Tab",        KEY_TAB },
    { "Caps_Lock",  KEY_CAPSLOCK },
    { "space",      KEY_SPACE },
    { "Down",       KEY_DOWN },
    { "Up",         KEY_UP },
    { "Left",       KEY_LEFT },
    { "Right",      KEY_RIGHT },
    { "Home",       KEY_HOME },
    { "End",        KEY_END },
    { "F1", KEY_F1 },  { "F2", KEY_F2 },  { "F3", KEY_F3 },
    { "F4", KEY_F4 },  { "F5", KEY_F5 },  { "F6", KEY_F6 },
    { "F7", KEY_F7 },  { "F8", KEY_F8 },  { "F9", KEY_F9 },
    { "F10", KEY_F10 }, { "F11", KEY_F11 }, { "F12", KEY_F12 },
};

static int name_to_code(const char *name)
{
    for (size_t i = 0; i < sizeof(key_names) / sizeof(key_names[0]); i++) {
        if (strcmp(name, key_names[i].name) == 0)
            return key_names[i].code;
    }
    if (strlen(name) == 1) {
        unsigned char c = (unsigned char) name[0];
        if (c >= 'a' && c <= 'z')
            return KEY_A + (c - 'a');
        if (c >= '0' && c <= '9')
            return (c == '0') ? KEY_0 : KEY_1 + (c - '1');
    }
    return -1;
}

/* --- ASCII -> (keycode, needs-shift) for type() --- */

static int ascii_to_key(unsigned char c, int *shift)
{
    *shift = 0;
    switch (c) {
    case 'a' ... 'z': return KEY_A + (c - 'a');
    case 'A' ... 'Z': *shift = 1; return KEY_A + (c - 'A');
    case '0': return KEY_0;
    case '1' ... '9': return KEY_1 + (c - '1');
    case ' ': return KEY_SPACE;
    case '-': return KEY_MINUS;
    case '=': return KEY_EQUAL;
    case '[': return KEY_LEFTBRACE;
    case ']': return KEY_RIGHTBRACE;
    case '\\': return KEY_BACKSLASH;
    case ';': return KEY_SEMICOLON;
    case '\'': return KEY_APOSTROPHE;
    case '`': return KEY_GRAVE;
    case ',': return KEY_COMMA;
    case '.': return KEY_DOT;
    case '/': return KEY_SLASH;
    case '_': *shift = 1; return KEY_MINUS;
    case '+': *shift = 1; return KEY_EQUAL;
    case '{': *shift = 1; return KEY_LEFTBRACE;
    case '}': *shift = 1; return KEY_RIGHTBRACE;
    case '|': *shift = 1; return KEY_BACKSLASH;
    case ':': *shift = 1; return KEY_SEMICOLON;
    case '"': *shift = 1; return KEY_APOSTROPHE;
    case '~': *shift = 1; return KEY_GRAVE;
    case '<': *shift = 1; return KEY_COMMA;
    case '>': *shift = 1; return KEY_DOT;
    case '?': *shift = 1; return KEY_SLASH;
    case '!': *shift = 1; return KEY_1;
    case '@': *shift = 1; return KEY_2;
    case '#': *shift = 1; return KEY_3;
    case '$': *shift = 1; return KEY_4;
    case '%': *shift = 1; return KEY_5;
    case '^': *shift = 1; return KEY_6;
    case '&': *shift = 1; return KEY_7;
    case '*': *shift = 1; return KEY_8;
    case '(': *shift = 1; return KEY_9;
    case ')': *shift = 1; return KEY_0;
    default: return -1;
    }
}

/* --- Device lifecycle --- */

static int dev_fd = -1;

static int set_bit(int what, int code)
{
    if (ioctl(dev_fd, what, (unsigned long) code) < 0) {
        fprintf(stderr, "ukey: ioctl(%s, %d): %s\n",
                what == UI_SET_EVBIT ? "UI_SET_EVBIT" :
                what == UI_SET_RELBIT ? "UI_SET_RELBIT" : "UI_SET_KEYBIT",
                code, strerror(errno));
        return -1;
    }
    return 0;
}

static int dev_create(void)
{
    static const int evbits[] = { EV_SYN, EV_KEY, EV_REL };
    static const int relbits[] = { REL_X, REL_Y };
    static const int keybits[] = {
        KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H,
        KEY_I, KEY_J, KEY_K, KEY_L, KEY_M, KEY_N, KEY_O, KEY_P,
        KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X,
        KEY_Y, KEY_Z,
        KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7,
        KEY_8, KEY_9,
        KEY_SPACE, KEY_ENTER, KEY_TAB, KEY_BACKSPACE, KEY_ESC,
        KEY_CAPSLOCK,
        KEY_LEFTSHIFT, KEY_LEFTCTRL, KEY_LEFTALT,
        KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN,
        KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN,
        KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6,
        KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12,
        KEY_MINUS, KEY_EQUAL, KEY_LEFTBRACE, KEY_RIGHTBRACE,
        KEY_BACKSLASH, KEY_SEMICOLON, KEY_APOSTROPHE, KEY_GRAVE,
        KEY_COMMA, KEY_DOT, KEY_SLASH,
        BTN_LEFT,
    };

    dev_fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (dev_fd < 0) {
        fprintf(stderr, "ukey: open /dev/uinput: %s\n", strerror(errno));
        return -1;
    }

    for (size_t i = 0; i < sizeof(evbits) / sizeof(evbits[0]); i++) {
        if (set_bit(UI_SET_EVBIT, evbits[i]) < 0)
            goto fail;
    }
    for (size_t i = 0; i < sizeof(relbits) / sizeof(relbits[0]); i++) {
        if (set_bit(UI_SET_RELBIT, relbits[i]) < 0)
            goto fail;
    }
    for (size_t i = 0; i < sizeof(keybits) / sizeof(keybits[0]); i++) {
        if (set_bit(UI_SET_KEYBIT, keybits[i]) < 0)
            goto fail;
    }

    struct uinput_setup us;
    memset(&us, 0, sizeof(us));
    strncpy(us.name, "gdm-harness", sizeof(us.name) - 1);
    us.id.bustype = BUS_USB;
    us.id.vendor = 0x1234;
    us.id.product = 0x5678;
    us.id.version = 0x0100;
    if (ioctl(dev_fd, UI_DEV_SETUP, &us) < 0) {
        fprintf(stderr, "ukey: UI_DEV_SETUP: %s\n", strerror(errno));
        goto fail;
    }
    if (ioctl(dev_fd, UI_DEV_CREATE) < 0) {
        fprintf(stderr, "ukey: UI_DEV_CREATE: %s\n", strerror(errno));
        goto fail;
    }

    /* O_NONBLOCK is required during setup on some kernels; the
     * device is fully created now, so blocking writes are safe. */
    int zero = 0;
    if (ioctl(dev_fd, FIONBIO, &zero) < 0) {
        fprintf(stderr, "ukey: clear O_NONBLOCK: %s\n", strerror(errno));
        goto fail;
    }
    return 0;

fail:
    close(dev_fd);
    dev_fd = -1;
    return -1;
}

static void dev_destroy(void)
{
    if (dev_fd < 0)
        return;
    ioctl(dev_fd, UI_DEV_DESTROY);
    close(dev_fd);
    dev_fd = -1;
}

/* --- Event emission --- */

static void write_event(unsigned type, unsigned code, int value)
{
    struct input_event ev;
    ev.type = type;
    ev.code = code;
    ev.value = value;
    ssize_t n = write(dev_fd, &ev, sizeof(ev));
    if (n != (ssize_t) sizeof(ev))
        die("write(input_event) failed");
}

static void key_press(int code)
{
    write_event(EV_KEY, (unsigned) code, 1);
    write_event(EV_SYN, 0, 0);
}

static void key_release(int code)
{
    write_event(EV_KEY, (unsigned) code, 0);
    write_event(EV_SYN, 0, 0);
}

static void send_key(int code, int with_shift)
{
    if (with_shift) {
        key_press(KEY_LEFTSHIFT);
        usleep(MOD_HOLD_US);
    }
    key_press(code);
    usleep(PRESS_HOLD_US);
    key_release(code);
    if (with_shift) {
        usleep(MOD_HOLD_US);
        key_release(KEY_LEFTSHIFT);
    }
}

static int mod_name_to_code(const char *name)
{
    if (strcmp(name, "ctrl") == 0)
        return KEY_LEFTCTRL;
    if (strcmp(name, "alt") == 0)
        return KEY_LEFTALT;
    if (strcmp(name, "shift") == 0)
        return KEY_LEFTSHIFT;
    return -1;
}

static long parse_long(const char *s, const char *what)
{
    char *end = NULL;
    long v = strtol(s, &end, 10);
    if (end == s || *end != '\0')
        die(what);
    return v;
}

int main(int argc, char **argv)
{
    if (argc < 2)
        usage();

    const char *cmd = argv[1];

    /* click takes no arguments; every other command does */
    if (strcmp(cmd, "click") == 0) {
        if (argc != 2)
            usage();
    } else if (strcmp(cmd, "type") != 0 && strcmp(cmd, "key") != 0 &&
               strcmp(cmd, "combo") != 0 && strcmp(cmd, "move") != 0) {
        usage();
    }

    if (dev_create() < 0)
        exit(3);
    usleep(CREATE_SETTLE_US);

    if (strcmp(cmd, "type") == 0) {
        if (argc != 3)
            usage();
        for (const char *p = argv[2]; *p != '\0'; p++) {
            unsigned char c = (unsigned char) *p;
            if (c < 0x20 || c > 0x7e)
                continue;  /* passwords are hex, usernames are lowercase */
            int shift = 0;
            int code = ascii_to_key(c, &shift);
            if (code < 0)
                continue;
            send_key(code, shift);
            usleep(CHAR_DELAY_US);
        }
    } else if (strcmp(cmd, "key") == 0) {
        if (argc != 3)
            usage();
        int code = name_to_code(argv[2]);
        if (code < 0)
            die("unknown key name");
        send_key(code, 0);
    } else if (strcmp(cmd, "combo") == 0) {
        int mods[8] = { 0 };
        int nmods = 0;
        int i = 2;
        while (i < argc - 1) {
            int code = mod_name_to_code(argv[i]);
            if (code < 0)
                die("unknown modifier (expected ctrl|alt|shift)");
            if (nmods >= 8)
                usage();
            mods[nmods++] = code;
            i++;
        }
        if (nmods == 0)
            usage();
        int code = name_to_code(argv[i]);
        if (code < 0)
            die("unknown key name");
        for (int m = 0; m < nmods; m++)
            key_press(mods[m]);
        usleep(MOD_HOLD_US);
        send_key(code, 0);
        for (int m = nmods - 1; m >= 0; m--) {
            key_release(mods[m]);
            usleep(10000);
        }
    } else if (strcmp(cmd, "move") == 0) {
        if (argc != 4)
            usage();
        long dx = parse_long(argv[2], "dx must be an integer");
        long dy = parse_long(argv[3], "dy must be an integer");
        /* Clamp absurd values; the compositor clamps the pointer to
         * the screen anyway, and overflow would wrap the int. */
        if (dx > 100000) dx = 100000;
        if (dx < -100000) dx = -100000;
        if (dy > 100000) dy = 100000;
        if (dy < -100000) dy = -100000;
        write_event(EV_REL, REL_X, (int) dx);
        usleep(MOTION_US);
        write_event(EV_REL, REL_Y, (int) dy);
        write_event(EV_SYN, 0, 0);
    } else {  /* click */
        key_press(BTN_LEFT);
        usleep(PRESS_HOLD_US);
        key_release(BTN_LEFT);
    }

    usleep(DESTROY_HOLD_US);
    dev_destroy();
    return 0;
}
