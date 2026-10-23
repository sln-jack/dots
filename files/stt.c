// stt [model.gguf]
//
// Stream mic speech into the focused X11 window, backspacing to follow model revisions. Escape stops.
// Each session is kept in $XDG_DATA_HOME/stt/<unix seconds>/{audio.wav,transcript.txt}.
#define _GNU_SOURCE
#include <X11/Xlib.h>
#include <X11/XKBlib.h>
#include <X11/extensions/Xinerama.h>
#include <X11/extensions/shape.h>
#include <X11/keysym.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <transcribe.h>
#include <transcribe/parakeet.h>

int XTestFakeKeyEvent(Display *, unsigned int, Bool, unsigned long);

#define MODEL "parakeet/parakeet-unified-en-0.6b-Q8_0.gguf"
#define RATE  16000
#define T     2
#define RED   0xff2222

static Display *dpy;
static KeyCode esc, bksp, shift;
static KeyCode scratch[16];
static KeySym scratch_sym[16];
static int nscratch, next_scratch;
static Window border;
static volatile sig_atomic_t stop;

static char *typed;
static size_t ntyped, captyped;

static int ignore(Display *d, XErrorEvent *e) { return 0; }
static void on_signal(int s) { stop = 1; }

static void on_log(transcribe_log_level lvl, const char *msg, void *u) {
    if (lvl == TRANSCRIBE_LOG_LEVEL_WARN || lvl == TRANSCRIBE_LOG_LEVEL_ERROR) fputs(msg, stderr);
}

// Monitor holding the focused window's center, else the pointer.
static void active_monitor(Window root, int *x, int *y, int *w, int *h) {
    Window focus, child;
    int revert, px, py, n;
    unsigned uw = 0, uh = 0, bw, depth;
    XGetInputFocus(dpy, &focus, &revert);
    if (focus > PointerRoot && focus != root && XGetGeometry(dpy, focus, &child, &px, &py, &uw, &uh, &bw, &depth))
        XTranslateCoordinates(dpy, focus, root, uw / 2, uh / 2, &px, &py, &child);
    else {
        unsigned mask;
        XQueryPointer(dpy, root, &child, &child, &px, &py, &revert, &revert, &mask);
    }
    *x = *y = 0;
    *w = DisplayWidth(dpy, DefaultScreen(dpy));
    *h = DisplayHeight(dpy, DefaultScreen(dpy));
    XineramaScreenInfo *m = XineramaQueryScreens(dpy, &n);
    for (int i = 0; m && i < n; i++)
        if (px >= m[i].x_org && px < m[i].x_org + m[i].width && py >= m[i].y_org && py < m[i].y_org + m[i].height) {
            *x = m[i].x_org; *y = m[i].y_org; *w = m[i].width; *h = m[i].height;
        }
    if (m) XFree(m);
}

// Click-through red frame around the active monitor while listening.
static void show_border(Window root) {
    int x, y, w, h;
    active_monitor(root, &x, &y, &w, &h);
    XSetWindowAttributes a = {.override_redirect = 1, .background_pixel = RED};
    border = XCreateWindow(dpy, root, x, y, w, h, 0, CopyFromParent, InputOutput, CopyFromParent,
                           CWOverrideRedirect | CWBackPixel, &a);
    XRectangle r[4] = {{0, 0, w, T}, {0, h - T, w, T}, {0, 0, T, h}, {w - T, 0, T, h}};
    XShapeCombineRectangles(dpy, border, ShapeBounding, 0, 0, r, 4, ShapeSet, Unsorted);
    XShapeCombineRectangles(dpy, border, ShapeInput, 0, 0, NULL, 0, ShapeSet, Unsorted);
    XMapRaised(dpy, border);
    XFlush(dpy);
}

static void tap(KeyCode kc, int shifted) {
    if (shifted) XTestFakeKeyEvent(dpy, shift, True, CurrentTime);
    XTestFakeKeyEvent(dpy, kc, True, CurrentTime);
    XTestFakeKeyEvent(dpy, kc, False, CurrentTime);
    if (shifted) XTestFakeKeyEvent(dpy, shift, False, CurrentTime);
}

static void find_scratch(void) {
    int lo, hi, per;
    XDisplayKeycodes(dpy, &lo, &hi);
    KeySym *map = XGetKeyboardMapping(dpy, lo, hi - lo + 1, &per);
    for (int kc = hi; kc >= lo && nscratch < 16; kc--) {
        int empty = 1;
        for (int i = 0; i < per; i++) if (map[(kc - lo) * per + i] != NoSymbol) empty = 0;
        if (empty) scratch[nscratch++] = kc;
    }
    XFree(map);
}

// Unmapped keysyms (e.g. accented letters) borrow a free keycode, round-robin.
static void type_sym(KeySym ks) {
    KeyCode kc = XKeysymToKeycode(dpy, ks);
    if (kc) {
        if (XkbKeycodeToKeysym(dpy, kc, 0, 0) == ks) return tap(kc, 0);
        if (XkbKeycodeToKeysym(dpy, kc, 0, 1) == ks) return tap(kc, 1);
    }
    if (!nscratch) return;
    for (int i = 0; i < nscratch; i++) if (scratch_sym[i] == ks) return tap(scratch[i], 0);
    int i = next_scratch++ % nscratch;
    KeySym pair[2] = {ks, ks};
    XChangeKeyboardMapping(dpy, scratch[i], 2, pair, 1);
    XSync(dpy, False);
    scratch_sym[i] = ks;
    tap(scratch[i], 0);
}

static int utf8_decode(const char *s, unsigned *cp) {
    unsigned char c = s[0];
    int n = c < 0x80 ? 1 : c < 0xe0 ? 2 : c < 0xf0 ? 3 : 4;
    *cp = n == 1 ? c : c & (0x3f >> (n - 1));
    for (int i = 1; i < n; i++) *cp = (*cp << 6) | (s[i] & 0x3f);
    return n;
}

static void type_text(const char *s, size_t n) {
    for (size_t i = 0; i < n;) {
        unsigned cp;
        i += utf8_decode(s + i, &cp);
        if (cp == '\n') type_sym(XK_Return);
        else type_sym(cp < 0x100 ? cp : 0x01000000 | cp);
    }
}

// Retype only the part of `want` that differs from what is already on screen.
static void sync_text(const char *want) {
    size_t n = strlen(want), common = 0;
    while (common < ntyped && common < n && typed[common] == want[common]) common++;
    while (common && (typed[common] & 0xc0) == 0x80) common--;
    if (common == ntyped && common == n) return;

    for (size_t i = common; i < ntyped; i++)
        if ((typed[i] & 0xc0) != 0x80) tap(bksp, 0);
    type_text(want + common, n - common);
    XFlush(dpy);

    if (n + 1 > captyped) typed = realloc(typed, captyped = 2 * (n + 1));
    memcpy(typed, want, n + 1);
    ntyped = n;
}

static void sync_session(struct transcribe_session *s) {
    const char *text = transcribe_full_text(s);
    if (text) sync_text(text);
}

static int lookahead(int ms, int *chunk, int *right) {
    switch (ms) {
    case 160:  *chunk = 80;   *right = 80;   return 0;
    case 320:  *chunk = 160;  *right = 160;  return 0;
    case 480:  *chunk = 160;  *right = 320;  return 0;
    case 1120: *chunk = 560;  *right = 560;  return 0;
    case 2080: *chunk = 1040; *right = 1040; return 0;
    }
    return 1;
}

static int session_dir(char *dir, size_t n) {
    const char *xdg = getenv("XDG_DATA_HOME"), *home = getenv("HOME");
    if (xdg && *xdg) snprintf(dir, n, "%s/stt", xdg);
    else if (home) snprintf(dir, n, "%s/.local/share/stt", home);
    else return 1;
    for (char *p = dir + 1; *p; p++)
        if (*p == '/') { *p = 0; mkdir(dir, 0755); *p = '/'; }
    mkdir(dir, 0755);
    size_t len = strlen(dir);
    snprintf(dir + len, n - len, "/%lld", (long long)time(NULL));
    return mkdir(dir, 0755) && errno != EEXIST;
}

// 16-bit mono WAV; sizes are patched in by wav_close.
static FILE *wav_open(const char *path) {
    FILE *f = fopen(path, "wb");
    if (!f) return NULL;
    uint8_t h[44] = "RIFF\0\0\0\0WAVEfmt \x10\0\0\0\x01\0\x01\0";
    uint32_t rate = RATE, bytes = RATE * 2;
    uint16_t align = 2, bits = 16;
    memcpy(h + 24, &rate, 4);
    memcpy(h + 28, &bytes, 4);
    memcpy(h + 32, &align, 2);
    memcpy(h + 34, &bits, 2);
    memcpy(h + 36, "data", 4);
    fwrite(h, 1, 44, f);
    return f;
}

static void wav_write(FILE *f, const float *pcm, size_t n) {
    int16_t out[RATE / 10];
    for (size_t i = 0; i < n; i++) {
        float v = pcm[i] < -1 ? -1 : pcm[i] > 1 ? 1 : pcm[i];
        out[i] = (int16_t)(v * 32767);
    }
    fwrite(out, 2, n, f);
}

static void wav_close(FILE *f) {
    uint32_t size = ftell(f), data = size - 44, riff = size - 8;
    fseek(f, 4, SEEK_SET);
    fwrite(&riff, 4, 1, f);
    fseek(f, 40, SEEK_SET);
    fwrite(&data, 4, 1, f);
    fclose(f);
}

static pid_t record(int *fd) {
    int p[2];
    if (pipe(p)) return -1;
    fcntl(p[0], F_SETPIPE_SZ, 1 << 20); // buffers ~16s of audio while the model loads
    pid_t pid = fork();
    if (pid == 0) {
        dup2(p[1], 1);
        close(p[0]);
        close(p[1]);
        execlp("pw-record", "pw-record", "--rate", "16000", "--channels", "1", "--format", "f32", "-", NULL);
        _exit(127);
    }
    close(p[1]);
    *fd = p[0];
    return pid;
}

int main(int argc, char **argv) {
    int ms = 320, opt;
    while ((opt = getopt(argc, argv, "l:")) != -1) {
        if (opt != 'l') goto usage;
        ms = atoi(optarg);
    }
    int chunk, right;
    if (lookahead(ms, &chunk, &right) || optind + 1 < argc) {
    usage:
        fprintf(stderr, "usage: stt [-l 160|320|480|1120|2080] [model.gguf]\n");
        return 2;
    }

    char model[PATH_MAX];
    if (optind < argc) {
        snprintf(model, sizeof model, "%s", argv[optind]);
    } else {
        char exe[PATH_MAX] = {0};
        if (readlink("/proc/self/exe", exe, sizeof exe - 1) < 0) return 1;
        snprintf(model, sizeof model, "%s/../../%s", dirname(exe), MODEL);
    }

    dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "stt: cannot open display\n"); return 1; }
    XSetErrorHandler(ignore);

    struct sigaction sa = {.sa_handler = on_signal};
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    int fd;
    pid_t rec = record(&fd);
    if (rec < 0) return 1;

    char dir[PATH_MAX - 32], path[PATH_MAX];
    FILE *wav = NULL;
    if (session_dir(dir, sizeof dir)) fprintf(stderr, "stt: cannot create session dir, not saving\n");
    else {
        snprintf(path, sizeof path, "%s/audio.wav", dir);
        wav = wav_open(path);
    }

    Window root = DefaultRootWindow(dpy);
    esc = XKeysymToKeycode(dpy, XK_Escape);
    bksp = XKeysymToKeycode(dpy, XK_BackSpace);
    shift = XKeysymToKeycode(dpy, XK_Shift_L);
    XGrabKey(dpy, esc, AnyModifier, root, True, GrabModeAsync, GrabModeAsync);
    find_scratch();
    show_border(root);

    transcribe_log_set(on_log, NULL);
    struct transcribe_session *s = NULL;
    transcribe_status st = transcribe_open(model, NULL, NULL, &s);
    if (st != TRANSCRIBE_OK) {
        fprintf(stderr, "stt: %s: %s\n", model, transcribe_status_string(st));
        kill(rec, SIGTERM);
        return 1;
    }

    struct transcribe_parakeet_buffered_stream_ext buf;
    transcribe_parakeet_buffered_stream_ext_init(&buf);
    buf.left_ms = 5600;
    buf.chunk_ms = chunk;
    buf.right_ms = right;
    struct transcribe_stream_params sp;
    transcribe_stream_params_init(&sp);
    sp.family = &buf.ext;
    st = transcribe_stream_begin(s, NULL, &sp);
    if (st != TRANSCRIBE_OK) {
        fprintf(stderr, "stt: stream_begin: %s\n", transcribe_status_string(st));
        kill(rec, SIGTERM);
        return 1;
    }

    float pcm[RATE / 10];
    size_t have = 0;
    while (!stop) {
        while (XPending(dpy)) {
            XEvent e;
            XNextEvent(dpy, &e);
            if (e.type == KeyPress && e.xkey.keycode == esc) stop = 1;
        }
        if (stop) break;

        ssize_t r = read(fd, (char *)pcm + have, sizeof pcm - have);
        if (r <= 0) break;
        have += r;
        size_t n = have / sizeof(float);
        if (!n) continue;
        if (wav) wav_write(wav, pcm, n);

        struct transcribe_stream_update upd;
        transcribe_stream_update_init(&upd);
        if (transcribe_stream_feed(s, pcm, n, &upd) != TRANSCRIBE_OK) break;
        if (upd.result_changed) sync_session(s);

        have -= n * sizeof(float);
        memmove(pcm, (char *)pcm + n * sizeof(float), have);
    }

    kill(rec, SIGTERM);
    waitpid(rec, NULL, 0);
    XDestroyWindow(dpy, border);

    struct transcribe_stream_update fin;
    transcribe_stream_update_init(&fin);
    if (transcribe_stream_finalize(s, &fin) == TRANSCRIBE_OK) sync_session(s);

    if (wav) {
        wav_close(wav);
        snprintf(path, sizeof path, "%s/transcript.txt", dir);
        FILE *t = fopen(path, "w");
        if (t) {
            fprintf(t, "%.*s\n", (int)ntyped, typed ? typed : "");
            fclose(t);
        }
    }

    XUngrabKey(dpy, esc, AnyModifier, root);
    for (int i = 0; i < nscratch; i++)
        if (scratch_sym[i]) {
            KeySym none[2] = {NoSymbol, NoSymbol};
            XChangeKeyboardMapping(dpy, scratch[i], 2, none, 1);
        }
    XSync(dpy, False);
    transcribe_session_free(s);
    XCloseDisplay(dpy);
    return 0;
}
