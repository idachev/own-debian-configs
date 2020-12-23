#!/usr/bin/env python

# ========================================
# Imports

import argparse
import hashlib
import multiprocessing
import numpy as np
import os
import pickle
import stat
import sys
import timeit
from multiprocessing import Queue, Process
from os import path

# ========================================
# Settings

DRY_RUN = True

WORKING_DIR = ".working"

FILES_DB = "files.db"

FILES_SRC_ROOT = "files_src"
FILES_DST_ROOT = "files_dst"

FILES_CACHE = ".files_cache"

UPDATE_DB = False

UPDATE_ROOT = False

DEFAULT_THREADS = multiprocessing.cpu_count() - 2
if DEFAULT_THREADS == 0:
    DEFAULT_THREADS = 1

# ========================================
# Defines

BUFF_FILE = 10 * 1024 * 1024

CHECK_DIR = ".check"
RECYCLE_DIR = ".recycle"

# ========================================
# Debugging

VERBOSE = False
DEBUG = False


def stdout_msg(msg):
    print(msg)
    sys.stdout.flush()
    sys.stderr.flush()


def stdout_msg_noln(msg):
    sys.stdout.write(msg)
    sys.stdout.flush()
    sys.stderr.flush()


def verbose(msg):
    if VERBOSE:
        stdout_msg("[INF] %s" % msg)


def verbose_nhdr(msg):
    if VERBOSE:
        stdout_msg_noln(msg)


def debug(msg):
    if DEBUG:
        stdout_msg("[DBG] %s" % msg)


def error(msg):
    stdout_msg("[ERR] %s" % msg)


# ========================================

class FilesDbItem:
    name = None
    size = 0
    mtime = 0
    hash = None
    duplicate = None

    def __init__(self, _name, _size, _mtime, _hash):
        self.name = _name
        self.size = _size
        self.mtime = _mtime
        self.hash = _hash
        self.duplicate = []


class CacheItem:
    path = None
    size = 0
    mtime = 0
    hash = None

    def __init__(self, _path, _size, _mtime, _hash):
        self.path = _path
        self.size = _size
        self.mtime = _mtime
        self.hash = _hash


def _calculate_hash_int_hashlib(file_path):
    """
    Calculate hash of a file, using internal python methods sha512
    """
    s = hashlib.sha512()

    with open(file_path, 'rb') as rfile:
        buf = rfile.read(BUFF_FILE)
        while len(buf) > 0:
            s.update(buf)
            buf = rfile.read(BUFF_FILE)

    return s.hexdigest()


def _calculate_hash(file_path, file_cache_map):
    """
    Calculate hash of a file

    I thought that the internal checksum is slower then this
    but actually it is USB mass storage buffer which when is
    freed then is starts really slow to read the files.
    But this is actually more reliable then coping files by hand.

    Use here only internal calculation and change to use sha1 plus md5.
    """
    debug('CH: %s' % file_path)

    size = path.getsize(file_path)
    mtime = os.stat(file_path)[stat.ST_MTIME]
    res_hash = None

    if file_path in file_cache_map:
        cache_item = file_cache_map[file_path]
        if cache_item.size == size and cache_item.mtime == mtime:
            res_hash = cache_item.hash

    if res_hash is None:
        res_hash = _calculate_hash_int_hashlib(file_path)
        file_cache_map[file_path] = CacheItem(file_path, size, mtime, res_hash)

    return res_hash


def part_multiprocess_hashes(queue, part_name, files_part, file_cache_map):
    verbose("Start processing part: %s files: %d" % (part_name, len(files_part)))

    hashes = {}
    for file_path in files_part:
        hashes[file_path] = _calculate_hash(file_path, file_cache_map)
        for i in range(1, 5):
            if len(hashes) == (i * len(files_part) / 4):
                verbose('Processed part: %s progress: %d%%' % (part_name, (25 * i)))
    queue.put(hashes)


def parts_multiprocess_hashes(files_parts, file_cache_map):
    processes = []

    part_i = 0
    for files_part in files_parts:
        queue = Queue()

        process = Process(
            target=part_multiprocess_hashes,
            args=(queue, part_i, files_part, file_cache_map))

        proc_data = [files_part, queue, process]
        processes.append(proc_data)

        process.start()

        part_i += 1

    files_parts_hashes = []
    for proc_data in processes:
        files_parts_hashes.append(proc_data[1].get())

    for proc_data in processes:
        proc_data[2].join()

    return files_parts_hashes


class FilesManage:
    _src_db_map = None
    _files_db = None
    _files_src_root = None
    _files_dst_root = None
    _working_dir = True
    _dry_run = True
    _files_cache = None
    _file_cache_map = None

    def __init__(self, files_db, files_src_root, files_dst_root, files_cache, working_dir, dry_run=True):
        self._files_db = files_db
        self._files_src_root = files_src_root
        self._files_dst_root = files_dst_root
        self._files_cache = files_cache
        self._working_dir = working_dir
        self._dry_run = dry_run

        verbose("files src db: %s" % self._files_db)
        verbose("files src root dir: %s" % self._files_src_root)
        verbose("files dst root dir: %s" % self._files_dst_root)
        verbose("files src/dst cache: %s" % self._files_cache)
        verbose("files working dir: %s" % self._working_dir)
        verbose("dry run: %d" % self._dry_run)

        self._src_db_map = self._read_db()
        self._file_cache_map = self._read_cache()

    def _read_db(self):
        """
        Parse our DB file.
        """
        data = self._read_pickle(self._files_db)

        db_map = {}
        if data is not None:
            for item in data:
                db_map[item.hash] = item

        return db_map

    def _write_db(self, db_map, file_path):
        """
        Write db file.
        """
        verbose("Writing DB file: %s" % file_path)
        self._write_pickle(db_map.values(), file_path)

    def _read_cache(self):
        """
        Parse our cache file.
        """
        data = self._read_pickle(self._files_cache)

        files_cache_map = {}
        if data is not None:
            for item in data:
                files_cache_map[item.path] = item

        return files_cache_map

    def _write_cache(self, file_cache_map, file_path):
        """
        Write file cache.
        """
        verbose("Writing file cache: %s" % file_path)
        self._write_pickle(file_cache_map.values(), file_path)

    def _write_pickle(self, data, file_path):
        """
        Write pickle data to file
        """
        if not self._dry_run:
            file_path_dir = path.dirname(file_path)
            if not path.exists(file_path_dir):
                os.makedirs(file_path_dir)

            if path.exists(file_path):
                bak_p = "_bak"
                i = 0
                while path.exists(file_path + bak_p):
                    bak_p = "_bak_" + str(i)
                    i += 1
                os.rename(file_path, file_path + bak_p)

            with open(file_path, 'wb') as f:
                pickle.dump(data, f)

    def _read_pickle(self, file_path):
        """
        Read pickle data from file
        """
        pickle_data = None
        if path.exists(file_path):
            with open(file_path, 'rb') as f:
                pickle_data = pickle.load(f)
        else:
            verbose("File does no exist will be created: %s" % file_path)

        return pickle_data

    def _fill_db(self, dir_path, db_map):
        """
        Fill DB from directory.
        """
        verbose("Fill db from: %s" % dir_path)
        all_files = []
        for root, dirs, files in os.walk(dir_path):
            files = (path.join(root, x) for x in files)
            for file_path in files:
                name = file_path[len(dir_path) + 1:]
                if (os.sep + '.') in name or name.startswith('.'):
                    continue
                all_files.append(file_path)

        parts = np.array_split(all_files, DEFAULT_THREADS)
        parts_res = parts_multiprocess_hashes(parts, self._file_cache_map)

        for hashes in parts_res:
            assert isinstance(hashes, dict)
            for file_path, res_hash in hashes.items():
                name = file_path[len(dir_path) + 1:]
                size = path.getsize(file_path)
                mtime = os.stat(file_path)[stat.ST_MTIME]
                self._add_to_file_cache_map(file_path, res_hash)
                self._add_to_db(db_map, dir_path, FilesDbItem(name, size, mtime, res_hash))
                verbose_nhdr("\rfiles: %d" % len(db_map))

        verbose_nhdr("\n")

    def _add_to_file_cache_map(self, file_path, res_hash):
        size = path.getsize(file_path)
        mtime = os.stat(file_path)[stat.ST_MTIME]

        if file_path in self._file_cache_map:
            cache_item = self._file_cache_map[file_path]
            if cache_item.size == size and cache_item.mtime == mtime \
                    and cache_item.hash == res_hash:
                return

        self._file_cache_map[file_path] = CacheItem(file_path, size, mtime, res_hash)

    def update_db(self):
        """
        Update db with the files root content.
        Do not cleanup old data in db.
        If there is existing file with same cache it is replaced.
        """
        verbose("Update DB")
        self._fill_db(self._files_src_root, self._src_db_map)

        self._write_db(self._src_db_map, self._files_db)

        self._write_cache(self._file_cache_map, self._files_cache)

        if self._dry_run:
            verbose("DRY RUN")

    def _add_to_db(self, db_map, root_dir, db_item):
        """
        Add item to db
        """
        debug("Add to db\n  name: %s\n  size: %d\n  hash: %s" %
              (db_item.name, db_item.size, db_item.hash))
        # check if we have this file in the db by hash
        if db_item.hash in db_map:
            existing_item = db_map[db_item.hash]
            if existing_item.name != db_item.name:
                if path.exists(path.join(root_dir, existing_item.name)):
                    if db_item.name not in existing_item.duplicate:
                        verbose("Found duplicate:\n  name: %s\n  name: %s" %
                                (existing_item.name, db_item.name))
                        existing_item.duplicate.append(db_item.name)
                else:
                    verbose("Replace none existing duplicate:\n  name: %s\n  name: %s" %
                            (existing_item.name, db_item.name))
                    db_map[db_item.hash] = db_item
        else:
            db_map[db_item.hash] = db_item

    def update_root(self):
        """
        Find files which are not in the right position and move them.
        """
        verbose("Update root")

        if len(self._src_db_map) == 0:
            error("Source DB is empty")
            sys.exit(101)

        if self._files_dst_root is None:
            error("Destination root directory should be set")
            sys.exit(102)

        # first create current root directory db
        rmap = {}
        self._fill_db(self._files_dst_root, rmap)

        values = rmap.values()
        # next remove duplicate move files
        for ritem in values:
            for dupitem in ritem.duplicate:
                verbose("Found duplicate:\n  name: %s" % dupitem)
                self._recycle(dupitem)
            ritem.duplicate = []

        # next move files to right location according the files source root DB
        for ritem in values:
            if ritem.hash in self._src_db_map:
                ditem = self._src_db_map[ritem.hash]
                if ditem.size != ritem.size:
                    verbose("Size mismatch:\n  old name: %s\n  old size: %d\n  new name: %s\n  new size: %d" % (
                        ritem.name, ritem.size, ditem.name, ditem.size))
                    continue
                if ditem.name != ritem.name:
                    f1 = path.join(self._files_dst_root, ritem.name)
                    f2 = path.join(self._files_dst_root, ditem.name)
                    verbose("Move files:\n  old name: %s\n  new name: %s" % (f1, f2))
                    if path.exists(f2):
                        if _calculate_hash(f2, self._file_cache_map) == ritem.hash:
                            verbose("Found duplicate:\n  name: %s" % ritem.name)
                            self._recycle(ritem.name)
                        else:
                            error("Destination already exist skip move:\n  file: %s:" % f2)
                    else:
                        if not self._dry_run:
                            os.renames(f1, f2)
                            os.utime(f2, (ditem.mtime, ditem.mtime))
            else:
                f1 = path.join(self._files_dst_root, ritem.name)
                f2 = path.join(self._files_dst_root, self._working_dir, CHECK_DIR, ritem.name)
                verbose("Not in DB move to:\n  name: %s" % f2)
                if path.exists(f2):
                    error("Destination already exist skip move:\n  file: %s:" % f2)
                else:
                    if not self._dry_run:
                        os.renames(f1, f2)

        self._write_cache(self._file_cache_map, self._files_cache)

        if self._dry_run:
            verbose("DRY RUN")

    def _recycle(self, name):
        """
        Move file to local RECYCLE_DIR
        """
        recycle_dir = path.join(self._files_dst_root, self._working_dir, RECYCLE_DIR)

        f1 = path.join(self._files_dst_root, name)
        f2 = path.join(recycle_dir, name)

        i = 0
        while path.exists(f2):
            f2 = path.join(recycle_dir, name + '_' + str(i))
            i += 1

        verbose("Recycle:\n  file: %s" % f2)

        if not self._dry_run:
            if not path.exists(recycle_dir):
                os.makedirs(recycle_dir)

            os.renames(f1, f2)


# ========================================


def parse_args():
    """
    Parse arguments and print help message if requested.
    """
    global DRY_RUN
    global DEBUG
    global VERBOSE
    global FILES_DB
    global FILES_SRC_ROOT
    global FILES_DST_ROOT
    global UPDATE_DB
    global UPDATE_ROOT
    global FILES_CACHE
    global WORKING_DIR

    parser = argparse.ArgumentParser(description='Script to manage files names and directory places')
    parser.add_argument('files_src_root', metavar='FILES_SRC_ROOT', nargs=1,
                        help='point to files source root dir')
    parser.add_argument('files_dst_root', metavar='FILES_DST_ROOT', nargs='?',
                        help='point to files destination root dir, required if -root/--update-root is used')
    parser.add_argument('-v', '--verbose',
                        dest="verbose",
                        action='store_true',
                        help='verbose messages')
    parser.add_argument('-vv', '--debug',
                        dest="debug",
                        action='store_true',
                        help='debug messages, implies verbose')
    parser.add_argument('-n', '--dry-run',
                        dest="dry_run",
                        action='store_true',
                        help='dry run')
    parser.add_argument('--working-dir',
                        dest='working_dir',
                        default=WORKING_DIR,
                        help='working dir name to store DB and files cache, default is "%s"' % WORKING_DIR)
    parser.add_argument('--files-db',
                        dest='files_db',
                        default=FILES_DB,
                        help='file name of the DB to use, default is "%s"' % FILES_DB)
    parser.add_argument('--files-cache',
                        dest='files_cache',
                        default=FILES_CACHE,
                        help='file name of the files cache to use, default is "%s"' % FILES_CACHE)
    parser.add_argument('-db', '--update-db',
                        dest='update_db',
                        action='store_true',
                        help='update the db with data from files root')
    parser.add_argument('-root', '--update-root',
                        dest='update_root',
                        action='store_true',
                        help='update the files root with data from db')

    args = parser.parse_args()

    DRY_RUN = args.dry_run
    DEBUG = args.debug
    VERBOSE = args.verbose or DEBUG
    FILES_DB = args.files_db
    FILES_SRC_ROOT = args.files_src_root
    FILES_DST_ROOT = args.files_dst_root
    UPDATE_DB = args.update_db
    UPDATE_ROOT = args.update_root
    FILES_CACHE = args.files_cache
    WORKING_DIR = args.working_dir

    if UPDATE_DB and UPDATE_ROOT:
        error("Only one of the -db/--update-db or -root/--update-root should be specified.")
        sys.exit(1)

    if (not UPDATE_DB) and (not UPDATE_ROOT):
        error("One of the -db/--update-db or -root/--update-root should be specified.")
        sys.exit(2)

    FILES_SRC_ROOT = path.abspath(FILES_SRC_ROOT[0])

    if FILES_DST_ROOT is not None:
        FILES_DST_ROOT = path.abspath(FILES_DST_ROOT)

    if UPDATE_DB and FILES_DST_ROOT is not None:
        error("Destination root directory should be not set when update DB: %s" % FILES_DST_ROOT)
        sys.exit(3)

    if UPDATE_ROOT and FILES_DST_ROOT is None:
        error("Destination root directory is required when update root")
        sys.exit(4)

    if not path.isdir(FILES_SRC_ROOT) or not path.exists(FILES_SRC_ROOT):
        error("Files source root is not a directory: %s" % FILES_SRC_ROOT)
        sys.exit(5)

    if FILES_DST_ROOT is not None and (not path.isdir(FILES_DST_ROOT) or not path.exists(FILES_DST_ROOT)):
        error("Files destination root is not a directory: %s" % FILES_DST_ROOT)
        sys.exit(6)

    if UPDATE_ROOT and FILES_DST_ROOT == FILES_SRC_ROOT:
        error("When updating root the source should be differ from destination: %s" % FILES_SRC_ROOT)
        sys.exit(7)

    if len(path.dirname(FILES_DB)) != 0:
        error("You cannot specify path in the files DB name: %s" % FILES_DB)
        sys.exit(8)

    if len(path.dirname(FILES_CACHE)) != 0:
        error("You cannot specify path in the files cache name: %s" % FILES_CACHE)
        sys.exit(9)

    if len(path.dirname(WORKING_DIR)) != 0:
        error("You cannot specify path in the working directory name: %s" % WORKING_DIR)
        sys.exit(10)

    FILES_DB = path.join(FILES_SRC_ROOT, WORKING_DIR, FILES_DB)
    if UPDATE_ROOT:
        FILES_CACHE = path.join(FILES_DST_ROOT, WORKING_DIR, FILES_CACHE)
    else:
        FILES_CACHE = path.join(FILES_SRC_ROOT, WORKING_DIR, FILES_CACHE)

    FILES_DB = path.abspath(FILES_DB)
    FILES_CACHE = path.abspath(FILES_CACHE)


def main():
    parse_args()

    t0 = timeit.default_timer()
    inst = FilesManage(FILES_DB, FILES_SRC_ROOT, FILES_DST_ROOT, FILES_CACHE, WORKING_DIR, DRY_RUN)
    verbose("Load DB for: %d seconds" % (timeit.default_timer() - t0))

    if UPDATE_DB:
        t0 = timeit.default_timer()
        inst.update_db()
        verbose("Update DB for: %d seconds" % (timeit.default_timer() - t0))
    elif UPDATE_ROOT:
        t0 = timeit.default_timer()
        inst.update_root()
        verbose("Update root for: %d seconds" % (timeit.default_timer() - t0))


# ========================================
if __name__ == '__main__':
    main()
