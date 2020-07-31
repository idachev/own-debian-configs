#!/usr/bin/env python
import os
import tempfile
from os import path
import cv2

# Need these:
# sudo -H pip2 install opencv-python
# sudo apt install python-gtk2 xdotool


def get_screenshot():
    import gtk.gdk

    w = gtk.gdk.get_default_root_window()
    sz = w.get_size()
    pb = gtk.gdk.Pixbuf(gtk.gdk.COLORSPACE_RGB, False, 8, sz[0], sz[1])
    pb = pb.get_from_drawable(w, w.get_colormap(), 0, 0, 0, 0, sz[0], sz[1])
    if pb is not None:
        (fd, tmp_path) = tempfile.mkstemp(suffix='.png')
        pb.save(tmp_path, "png")
        os.close(fd)
        return tmp_path
    else:
        raise Exception("Unable to get the screenshot.")


def main():
    method = cv2.TM_SQDIFF_NORMED

    small_image = cv2.imread(path.join(path.dirname(__file__),
                                       'recoll/recoll-tray-icon.png'))
    w = small_image.shape[0]
    h = small_image.shape[1]

    screenshot_file = get_screenshot()

    large_image = cv2.imread(screenshot_file)

    res = cv2.matchTemplate(small_image, large_image, method)

    min_val, max_val, min_loc, max_loc = cv2.minMaxLoc(res)

    top_left = min_loc
    center = (top_left[0] + w/2, top_left[1] + h/2)

    os.system('xdotool mousemove --sync %d %d' %
              (center[0], center[1]))
    os.system('xdotool click 1')

    os.remove(screenshot_file)


if __name__ == '__main__':
    main()
