#!/usr/bin/env python

import os
import re
from os import path
import shutil
import sys

MATCH = re.compile('(.+) \(.* conflicted copy [0-9-]+\)')

def fix_conflicts(path_to_fix):
    print('Fix conflicts: %s' % path_to_fix)
    for dirpath, dnames, fnames in os.walk(path_to_fix):
        for f in fnames:
            m = MATCH.match(f)
            if m:
                name = m.group(1)
                dst = path.join(dirpath, name)
                if path.exists(dst):
                    dst_mtime = path.getmtime(dst)
                    src = path.join(dirpath, f)
                    src_mtime = path.getmtime(src)

                    if src_mtime > dst_mtime:
                        print('\n Found\n\tmtime: %d\n\tfile: %s\n\tmtime: %d\n\t: file: %s' %
                              (src_mtime, src, dst_mtime, dst))
                        shutil.move(dst, dst + '_backup_')
                        shutil.move(src, dst)

if __name__ == '__main__':
    path_to_fix = sys.argv[1]
    fix_conflicts(path_to_fix)
