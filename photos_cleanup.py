#!/usr/bin/env python

import sys

from os.path import basename, expanduser

import os

from send2trash import send2trash


def trash_all_from(photo_to_delete, dir_to_look):
    print('Look for:\n  %s\nIn tree:\n  %s' % (photo_to_delete, dir_to_look))

    name = basename(photo_to_delete).lower()

    matches = []
    for root, dirnames, filenames in os.walk(dir_to_look):
        for filename in filenames:
            if filename.lower() == name:
                matches.append(os.path.join(root, filename))

    if len(matches) > 0:
        for match in matches:
            print('Trash\n  %s' % match)
            send2trash(match)
    else:
        print('\nNot found')


def main():
    if len(sys.argv) != 3:
        print('Expected 2 arguments: <photo to delete> <directory to look for>')
        sys.exit(1)

    photo_to_delete = expanduser(sys.argv[1])
    dir_to_look = expanduser(sys.argv[2])
    trash_all_from(photo_to_delete, dir_to_look)


if __name__ == '__main__':
    main()
