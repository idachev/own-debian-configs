#!/usr/bin/env python
import filecmp

import os
from os import path
import shutil
import sys

def fix_duplicate_case_file_names(path_to_fix):
    print('Fix conflicts: %s' % path_to_fix)
    files = os.listdir(path_to_fix)
    lower_case_map = {}
    for fname in files:
        fpath = path.join(path_to_fix, fname)
        if path.isfile(fpath):
            fname_l = fname.lower()
            if fname_l not in lower_case_map:
                lower_case_map[fname_l] = []
            lower_case_map[fname_l].append(fpath)

    for dups in lower_case_map.values():
        if len(dups) == 1:
            continue

        f0 = dups[0]
        for i in range(1, len(dups)):
            fx = dups[i]
            if filecmp.cmp(f0, fx, shallow=False):
                print('\n\nFound same duplicates:\n\t%s\n\t%s' % (f0, fx))
                print('Delete\n\t%s' % fx)
                os.remove(fx)
            else:
                print('\n\nFound different duplicates:\n\t%s\n\t%s' % (f0, fx))
                fxp, fxe = path.splitext(fx)
                fxpb = fxp + '_'
                while(path.exists(fxpb + fxe)):
                    fxpb += '_'
                fxn = fxpb + fxe
                print('Rename to\n\t%s' % fxn)
                shutil.move(fx, fxn)

if __name__ == '__main__':
    path_to_fix = sys.argv[1]
    fix_duplicate_case_file_names(path_to_fix)
