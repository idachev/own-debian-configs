#!/usr/bin/python3

"""Usage:
  pgdump-sort <dump> [<sorted-dump>]
  pgdump-sort -h | --help | --version

  Author:
  https://github.com/tigra564/pgdump-sort

  Fixed to use natsorted
"""

import os
import re
import shutil
import tempfile
from enum import Enum

from docopt import docopt
from natsort import natsorted, ns

version = '0.2'

RE_OBJDESC = re.compile(
    '-- (?P<isdata>(Data for )?)Name: (?P<name>.*?); '
    'Type: (?P<type>.*?); '
    'Schema: (?P<schema>.*?); '
    'Owner: (?P<owner>.*)'
)
RE_SEQSET = re.compile("SELECT pg_catalog.setval\('(?P<name>.*?)'.*")


class state(Enum):
    EMPTY = 1
    SETTINGS = 2
    DEF = 3
    DATA = 4
    COPY = 5
    INSERT = 6
    SEQSET = 7


class buffer(list):
    destdir = None
    st = state.EMPTY
    fname = None
    title = None

    def __init__(self, destdir):
        self.destdir = destdir

    def flushto(self, st, fname, title):
        # print("EVICTING", self.st, "to", self.fname, "New state:", st)

        # Trim ellipsing comments and empty lines
        while self and ('' == self[0] or self[0].startswith('--')):
            del self[0]
        while self and ('' == self[-1] or self[-1].startswith('--')):
            del self[-1]

        if len(self):
            if self.st in (state.COPY, state.INSERT):
                self[:] = sort_datalines(self)

            self[:] = [
                          '--',
                          self.title,
                          '--',
                          '',
                      ] + self

            with open(os.path.join(self.destdir, self.fname), "w") as out:
                out.writelines([l + '\n' for l in self])

        self.clear()
        self.st = st
        self.fname = fname
        self.title = title

    def proc_comment(self, line):
        # Returns True if the line is a comment, i.e. it has been processed
        if not line.startswith('--'):
            return False

        m = re.match(RE_OBJDESC, line)
        if not m:
            return True

        if 'SEQUENCE SET' == m.group('type'):
            st = state.SEQSET
        elif m.group('isdata'):
            st = state.DATA
        else:
            st = state.DEF

        fname = '%d-%s-%s-%s-%s' % (
            st.value,
            m.group('type'),
            m.group('schema'),
            m.group('name'),
            m.group('owner')
        )

        if 255 < len(fname):
            fname = fname[:255 - 3] + "..."

        self.flushto(st, fname, line)

        return True


def sort_datalines(lines):
    pre = []
    data = []
    post = []

    state = 0
    ptr = pre
    isins = False
    for line in lines:
        if 0 == state:
            if line.startswith('COPY'):
                ptr.append(line)
                ptr = data
                state = 1
            elif line.startswith('INSERT'):
                ptr = data
                ptr.append(line)
                isins = True
                state = 1
            else:
                ptr.append(line)
        elif 1 == state:
            if isins and '\n' == line or not isins and '\\.\n' == line:
                ptr = post
                ptr.append(line)
                status = 2
            else:
                ptr.append(line)
        else:
            ptr.append(line)

    return pre + natsorted(data, alg=ns.IGNORECASE) + post


def dissect(dump, destdir):
    buf = buffer(destdir)

    for line in open(dump):
        # trim trailing newline (if any)
        if '\n' == line[-1]:
            line = line[:-1]

        # print(buf.st.name.ljust(10), "\t[%s]" % line)
        if buf.st == state.EMPTY:
            if buf.proc_comment(line):
                pass
            elif '' == line:
                pass
            else:
                buf.flushto(state.SETTINGS, "%d-%s" % (state.SETTINGS.value, "SETTINGS"),
                            '-- Sorted PostgreSQL database dump')
                buf.append(line)

        elif buf.st in (state.SETTINGS, state.DEF, state.INSERT):
            if buf.proc_comment(line):
                pass
            else:
                buf.append(line)

        elif buf.st == state.DATA:
            if line.startswith('COPY '):
                buf.st = state.COPY
            elif line.startswith('INSERT '):
                buf.st = state.INSERT
            buf.append(line)

        elif buf.st == state.COPY:
            buf.append(line)
            if r'\.' == line:
                buf.flushto(state.EMPTY, None, None)

        elif buf.st == state.SEQSET:
            if buf.proc_comment(line):
                pass
            elif line.startswith('SELECT pg_catalog.setval'):
                m = re.match(RE_SEQSET, line)
                line = "SELECT pg_catalog.setval('%s', 1, false);" % m.group('name')
                buf.append(line)
            else:
                buf.append(line)

        else:
            print("This should not happen")

    buf.flushto(state.EMPTY, None, None)


def recombine(destdir, dump):
    out = open(dump, 'w')

    first = True
    sorted_files = sorted(os.listdir(destdir))
    for fname in sorted_files:
        if first:
            first = False
        else:
            out.write('\n')
        with open(os.path.join(destdir, fname)) as f:
            out.writelines(f.readlines())

    if sorted_files:
        out.writelines([
            '\n',
            '--\n',
            '-- Sorted dump complete\n',
            '--\n',
        ])

    out.close()


def pgdump_sort(dump, sdump):
    destdir = tempfile.mkdtemp(suffix=os.path.basename(dump), prefix='pgdump-sort')

    try:
        dissect(dump, destdir)
        recombine(destdir, sdump)

    finally:
        shutil.rmtree(destdir)


if __name__ == '__main__':
    args = docopt(__doc__, version=version)

    dump = args['<dump>']
    sdump = args['<sorted-dump>']
    if sdump is None:
        sdump = re.sub(r'\.sql$', '', dump) + '-sorted.sql'

    pgdump_sort(dump, sdump)
