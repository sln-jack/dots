// cc sshot.c -O2 -lX11 -lXext -o sshot
//
// Drag to select a region, screenshot, and copy to the clipboard.
#include <X11/Xlib.h>
#include <X11/extensions/shape.h>
#include <X11/keysym.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define T    2
#define RED  0xff2222
#define GRAY 0x808080

static Display *dpy;
static Window root, guide, box;
static KeyCode esc;
static int sw, sh;
static int sx, sy, x, y, w, h;

static int ignore(Display *d, XErrorEvent *e) { return 0; }

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
    usleep(50000); // let apps repaint old pixels before capture
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

static int deliver(void) {
    XImage *img = XGetImage(dpy, root, x, y, w, h, AllPlanes, ZPixmap);
    if (!img || img->bits_per_pixel != 32) return 1;

    char cmd[256];
    snprintf(cmd, sizeof cmd, "ffmpeg -loglevel error -f rawvideo -pix_fmt bgr0 -video_size %dx%d -i -"
             " -frames:v 1 -c:v png -f image2pipe -"
             " | setsid xclip -selection clipboard -t image/png", w, h);
    FILE *p = popen(cmd, "w");
    if (!p) return 1;
    for (int r = 0; r < h; r++)
        fwrite(img->data + r * img->bytes_per_line, 4, w, p);
    XDestroyImage(img);
    return pclose(p) != 0;
}

int main(void) {
    dpy = XOpenDisplay(NULL);
    if (!dpy) return 1;
    XSetErrorHandler(ignore);
    root = DefaultRootWindow(dpy);
    esc = XKeysymToKeycode(dpy, XK_Escape);
    sw = DisplayWidth(dpy, DefaultScreen(dpy));
    sh = DisplayHeight(dpy, DefaultScreen(dpy));

    if (select_region()) return 1;
    return deliver();
}
