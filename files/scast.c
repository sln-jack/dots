// cc scast.c -O2 -lX11 -lXext -o scast
//
// Drag to select a region, record an mp4, ctrl-escape to end, and copy to the clipboard.
#include <X11/Xlib.h>
#include <X11/extensions/shape.h>
#include <X11/keysym.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define RUN  "/tmp/scast"
#define RAW  RUN "/raw.mkv"
#define T    2
#define RED  0xff2222
#define GRAY 0x808080

static Display *dpy;
static Window root, guide, box;
static KeyCode esc;
static int sw, sh;
static int sx, sy, x, y, w, h;
static volatile sig_atomic_t stop;

static void on_usr1(int sig) { stop = 1; }
static int ignore(Display *d, XErrorEvent *e) { return 0; }

static int stop_running(void) {
    FILE *f = fopen(RUN "/pid", "r");
    if (!f) return 0;

    int pid, live = fscanf(f, "%d", &pid) == 1 && !kill(pid, 0);
    fclose(f);
    if (live) kill(pid, SIGUSR1);
    return live;
}

static Window window(unsigned long color) {
    XSetWindowAttributes a = {.override_redirect = 1, .background_pixel = color};
    Window win = XCreateWindow(dpy, root, 0, 0, sw, sh, 0, CopyFromParent, InputOutput,
                               CopyFromParent, CWOverrideRedirect | CWBackPixel, &a);
    XShapeCombineRectangles(dpy, win, ShapeBounding, 0, 0, NULL, 0, ShapeSet, Unsorted);
    XShapeCombineRectangles(dpy, win, ShapeInput, 0, 0, NULL, 0, ShapeSet, Unsorted);
    XMapRaised(dpy, win);
    return win;
}

static void outline(void) {
    XRectangle b[4] = {
        {x - T, y - T, w + 2*T, T},
        {x - T, y + h, w + 2*T, T},
        {x - T, y - T, T, h + 2*T},
        {x + w, y - T, T, h + 2*T},
    };
    XShapeCombineRectangles(dpy, box, ShapeBounding, 0, 0, b, 4, ShapeSet, Unsorted);
}

static void crosshair(int gx, int gy, int armed) {
    XRectangle g[2] = {
        {0, !armed || gy >= sy ? gy : gy - T, sw, T},
        {!armed || gx >= sx ? gx : gx - T, 0, T, sh},
    };
    XShapeCombineRectangles(dpy, guide, ShapeBounding, 0, 0, g, 2, ShapeSet, Unsorted);
}

static int select_region(void) {
    char none = 0;
    XColor black = {0};
    Pixmap pm = XCreateBitmapFromData(dpy, root, &none, 1, 1);
    Cursor cur = XCreatePixmapCursor(dpy, pm, pm, &black, &black, 0, 0);
    XFreePixmap(dpy, pm);
    if (XGrabPointer(dpy, root, False, ButtonPressMask | ButtonReleaseMask | PointerMotionMask,
                     GrabModeAsync, GrabModeAsync, root, cur, CurrentTime) != GrabSuccess) return 1;
    XGrabKeyboard(dpy, root, False, GrabModeAsync, GrabModeAsync, CurrentTime);

    Window dummy, pick = 0;
    unsigned mask;
    int wx, wy, gx, gy, armed = 0, cancel = 0;
    XQueryPointer(dpy, root, &dummy, &dummy, &gx, &gy, &wx, &wy, &mask);
    guide = window(GRAY);
    box = window(RED);
    crosshair(gx, gy, 0);

    for (;;) {
        XEvent e;
        XNextEvent(dpy, &e);

        if (e.type == KeyPress && e.xkey.keycode == esc) { cancel = 1; break; }
        if (e.type == ButtonPress) {
            sx = e.xbutton.x_root;
            sy = e.xbutton.y_root;
            pick = e.xbutton.subwindow;
            armed = 1;
        }
        if (e.type == MotionNotify || e.type == ButtonRelease) {
            if (e.type == MotionNotify) {
                while (XCheckTypedEvent(dpy, MotionNotify, &e));
                gx = e.xmotion.x_root;
                gy = e.xmotion.y_root;
            } else {
                gx = e.xbutton.x_root;
                gy = e.xbutton.y_root;
            }
            if (armed) {
                x = gx < sx ? gx : sx; w = abs(gx - sx);
                y = gy < sy ? gy : sy; h = abs(gy - sy);
            }
            if (e.type == ButtonRelease && armed) break;
            crosshair(gx, gy, armed);
            if (armed) outline();
        }
    }

    XDestroyWindow(dpy, guide);
    XUngrabPointer(dpy, CurrentTime);
    XUngrabKeyboard(dpy, CurrentTime);
    XFreeCursor(dpy, cur);
    XSync(dpy, False);
    usleep(50000);
    if (cancel) return 1;

    if (w < 8 && h < 8) {
        unsigned uw, uh, bw, depth;
        if (!pick || !XGetGeometry(dpy, pick, &dummy, &x, &y, &uw, &uh, &bw, &depth)) return 1;
        w = uw + 2*bw;
        h = uh + 2*bw;
        outline();
    }
    return !w || !h;
}

static pid_t record(void) {
    char size[32], input[64];
    snprintf(size, sizeof size, "%dx%d", w, h);
    snprintf(input, sizeof input, "%s+%d,%d", getenv("DISPLAY"), x, y);

    pid_t pid = fork();
    if (!pid) {
        dup2(open("/dev/null", O_RDONLY), 0);
        dup2(open(RUN "/log", O_WRONLY | O_CREAT, 0644), 1);
        dup2(1, 2);
        execlp("ffmpeg", "ffmpeg", "-loglevel", "error", "-f", "x11grab",
               "-framerate", "30", "-video_size", size, "-i", input,
               "-c:v", "ffv1", "-level", "3", "-slices", "16", "-threads", "8", RAW, (char *)NULL);
        _exit(127);
    }
    return pid;
}

static int encode(char *out) {
    time_t now = time(NULL);
    strftime(out, 64, "/tmp/scast-%Y%m%d-%H%M%S.mp4", localtime(&now));

    char cmd[256];
    snprintf(cmd, sizeof cmd, "ffmpeg -loglevel error -i " RAW " -vf mpdecimate -fps_mode vfr"
             " -c:v libsvtav1 -preset 8 -crf 38 -svtav1-params tune=0 -pix_fmt yuv420p"
             " -movflags +faststart %s 2>>" RUN "/log", out);
    return system(cmd);
}

static void human(long n, char *buf) {
    const char *unit = "BKMG";
    double v = n;
    while (v >= 1000 && unit[1]) { v /= 1024; unit++; }
    sprintf(buf, v < 10 && *unit != 'B' ? "%.1f%c" : "%.0f%c", v, *unit);
}

static void deliver(const char *out) {
    struct stat st;
    stat(out, &st);
    char size[8], cmd[256];
    human(st.st_size, size);

    snprintf(cmd, sizeof cmd, "printf 'file://%s\\n' | setsid xclip -selection clipboard -t text/uri-list", out);
    system(cmd);
    snprintf(cmd, sizeof cmd, "notify-send scast 'copied %s  %s'", size, out);
    system(cmd);
}

int main(void) {
    if (stop_running()) return 0;

    dpy = XOpenDisplay(NULL);
    if (!dpy) return 1;
    XSetErrorHandler(ignore);
    root = DefaultRootWindow(dpy);
    esc = XKeysymToKeycode(dpy, XK_Escape);
    sw = DisplayWidth(dpy, DefaultScreen(dpy));
    sh = DisplayHeight(dpy, DefaultScreen(dpy));

    if (select_region()) return 1;
    w &= ~1; h &= ~1; // yuv420 needs even dimensions
    if (w < 2 || h < 2) return 1;
    outline();

    system("rm -rf " RUN);
    mkdir(RUN, 0755);

    unsigned locks[] = {0, LockMask, Mod2Mask, LockMask | Mod2Mask};
    for (int i = 0; i < 4; i++)
        XGrabKey(dpy, esc, ControlMask | locks[i], root, True, GrabModeAsync, GrabModeAsync);
    XSync(dpy, False);

    pid_t ff = record();
    FILE *f = fopen(RUN "/pid", "w");
    fprintf(f, "%d", getpid());
    fclose(f);
    signal(SIGUSR1, on_usr1);

    while (!stop) {
        XEvent e;
        while (XPending(dpy)) {
            XNextEvent(dpy, &e);
            if (e.type == KeyPress && e.xkey.keycode == esc && e.xkey.state & ControlMask) stop = 1;
        }
        if (waitpid(ff, NULL, WNOHANG) == ff) { ff = 0; break; }
        nanosleep(&(struct timespec){0, 50000000}, NULL);
    }

    unlink(RUN "/pid");
    if (ff) { kill(ff, SIGINT); waitpid(ff, NULL, 0); }
    XUngrabKey(dpy, esc, AnyModifier, root);
    XSetWindowBackground(dpy, box, GRAY);
    XClearWindow(dpy, box);
    XSync(dpy, False);

    char out[64];
    int err = encode(out);
    XCloseDisplay(dpy);
    if (err) return system("notify-send scast 'encode failed, see " RUN "/log'"), 1;

    system("rm -rf " RUN);
    deliver(out);
    return 0;
}
