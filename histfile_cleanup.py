#!/usr/bin/env python

import sys
import os

check_starts_withs = [
    'cd ',
    'cp ',
    'sudo cp ',
    'rm ',
    'sudo rm ',
    'mkdir ',
    'sudo mkdir ',
    'ncdu ',
    'psg ',
    'sudo ncdu ',
    'l ',
    'ls ',
    'll ',
    'lla ',
    'cmp ',
    'n19 cp ',
    'n19 mv ',
    'n19 ls ',
    'ln ',
    'mv ',
    'kate ',
    'chmod ',
    'sudo chmod ',
    'vim ',
    'sudo vim ',
    'cat ',
    'sudo cat ',
    'kill ',
    'sudo kill ',
    'killall ',
    'sudo killall ',
    'git ci ',
    'g ci ',
    'git co ',
    'g co ',
    'git push ',
    'g push ',
    'git pull',
    'g pull',
    'git rebase ',
    'g rebase ',
    'git diff ',
    'g diff ',
    'git add ',
    'g add ',
    'git br ',
    'g br ',
    'git apply ',
    'g apply ',
    'git merge ',
    'g merge ',
    'git tag ',
    'g tag ',
    'gitka -- ',
    'gka -- ',
    'gitk -- ',
    'gk -- ',
    ]


def histfile_cleanup(file_path):
    hist_lines = read_histfile(file_path)

    hist_lines_unique = []
    for line in hist_lines:
        if line not in hist_lines_unique:
            hist_lines_unique.append(line)
    hist_lines = hist_lines_unique

    # hist_lines = sorted(hist_lines)

    new_hist_lines = []
    for line in hist_lines:
        if remove_hist_line(line):
            continue
        new_hist_lines.append(line)

    write_histfile(new_hist_lines, file_path + '_new')


def remove_hist_line(line):
    if len(line) > 1:
        return False

    for check_starts_with in check_starts_withs:
        if line[0].startswith(check_starts_with):
            return True

    return False


def write_histfile(hist_lines, file_path):
    print('Writing %d lines to %s' % (len(hist_lines), file_path))
    with open(file_path, 'wt') as f:
        for line in hist_lines:
            f.writelines(line)


def read_histfile(file_path):
    print('Reading from %s' % file_path)

    hist_lines = []
    next_line = []
    with open(file_path, 'rt') as f:
        for line in f:
            next_line.append(line)

            lch = count_lchar(line, '\\')
            if len(line) > 0 and lch > 0 and (lch % 2 != 0):
                continue

            hist_lines.append(next_line)
            next_line = []

    print('Read %d lines' % len(hist_lines))

    return hist_lines


def count_lchar(str, c):
    if str.endswith('\r\n'):
        str = str[:-2]
    elif str.endswith('\n'):
        str = str[:-1]
    res = 0
    for i in range(len(str) - 1, -1, -1):
        if str[i] != c:
            break
        else:
            res += 1
    return res


def main():
    if len(sys.argv) != 2:
        print('Expecting one argument the histfile path')
        sys.exit(1)

    hist_file = os.path.expanduser(sys.argv[1])
    histfile_cleanup(hist_file)


if __name__ == "__main__":
    main()
