#!/usr/bin/env python

import argparse
import hashlib
# ========================================
# Settings
import multiprocessing
import numpy as np
import os
import pickle
import stat
import sys
import time
from multiprocessing import Queue, Process
from os import path

DRY_RUN = True

PHOTOS_DB = "photos.db"
PHOTOS_ROOT = "photos"

FILE_CACHE = ".file_cache"

UPDATE_DB = False

UPDATE_ROOT = False

DEFAULT_THREADS = multiprocessing.cpu_count() - 2
if DEFAULT_THREADS == 0:
    DEFAULT_THREADS = 1

# ========================================
# Defines

BUFF_FILE = 512 * 1024

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
        stdout_msg("[INF] %s" % (msg))


def verbose_nhdr(msg):
    if VERBOSE:
        stdout_msg_noln(msg)


def debug(msg):
    if DEBUG:
        stdout_msg("[DBG] %s" % (msg))


def error(msg):
    stdout_msg("[ERR] %s" % (msg))


# ========================================

class PhotosDbItem:
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


def _calculate_hash_int(file_path):
    """
    Calculate hash of a file, using internal python methods sha1 + md5
    """
    s = hashlib.sha1()
    m = hashlib.md5()

    with open(file_path, 'rb') as rfile:
        buf = rfile.read(BUFF_FILE)
        while len(buf) > 0:
            s.update(buf)
            m.update(buf)
            buf = rfile.read(BUFF_FILE)

    return s.hexdigest() + m.hexdigest()


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
    hash = None

    if file_cache_map.has_key(file_path):
        cache_item = file_cache_map[file_path]
        if cache_item.size == size and cache_item.mtime == mtime:
            hash = cache_item.hash

    if hash is None:
        hash = _calculate_hash_int(file_path)
        file_cache_map[file_path] = CacheItem(file_path, size, mtime, hash)

    return hash


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


class PhotosManage:
    _db_map = None
    _photos_db = None
    _photos_root = None
    _dry_run = True
    _file_cache = None
    _file_cache_map = None

    def __init__(self, photos_db, photos_root, file_cache, dry_run=True):
        self._photos_db = photos_db
        self._photos_root = photos_root
        self._file_cache = file_cache
        self._dry_run = dry_run

        verbose("photos db: %s" % (self._photos_db))
        verbose("photos root dir: %s" % (self._photos_root))
        verbose("file cache: %s" % (self._file_cache))
        verbose("dry run: %d" % (self._dry_run))

        self._db_map = self._read_db()
        self._file_cache_map = self._read_cache()

    def _read_db(self):
        """
        Parse our DB file.
        """
        db_map = {}
        if path.exists(self._photos_db):
            with open(self._photos_db, 'rb') as rfile:
                db_data = pickle.load(rfile)
            for dbitem in db_data:
                db_map[dbitem.hash] = dbitem
        else:
            verbose("Photos DB file does no exist will be created: %s" % (self._photos_db))

        return db_map

    def _write_db(self, db_map, file_path):
        """
        Write db file.
        """
        verbose("Writing DB file: %s" % (file_path))
        self._write_pickle(db_map.values(), file_path)

    def _write_pickle(self, data, file_path):
        """
        Write pickle to file with backup DB file.
        """
        if not self._dry_run:
            if path.exists(file_path):
                bak_p = "_bak"
                i = 0
                while path.exists(file_path + bak_p):
                    bak_p = "_bak_" + str(i)
                    i += 1
                os.rename(file_path, file_path + bak_p)

            with open(file_path, 'wb') as wfile:
                pickle.dump(data, wfile)

    def _read_cache(self):
        """
        Parse our cache file.
        """
        file_cache_map = {}
        if path.exists(self._file_cache):
            with open(self._file_cache, 'rb') as rfile:
                data = pickle.load(rfile)
            for item in data:
                file_cache_map[item.path] = item
        else:
            verbose("File cache does no exist will be created: %s" % (self._file_cache))

        return file_cache_map

    def _write_cache(self, file_cache_map, file_path):
        """
        Write file cache.
        """
        verbose("Writing file cache: %s" % (file_path))
        self._write_pickle(file_cache_map.values(), file_path)

    def _fill_db(self, dir, db_map):
        """
        Fill DB from directory.
        """
        verbose("Fill db from: %s" % dir)
        all_files = []
        for root, dirs, files in os.walk(dir):
            files = (path.join(root, x) for x in files)
            for file_path in files:
                name = file_path[len(dir) + 1:]
                if (os.sep + '.') in name or name.startswith('.'):
                    continue
                all_files.append(file_path)

        parts = np.array_split(all_files, DEFAULT_THREADS)
        parts_res = parts_multiprocess_hashes(parts, self._file_cache_map)

        for hashes in parts_res:
            assert isinstance(hashes, dict)
            for file_path, hash in hashes.items():
                name = file_path[len(dir) + 1:]
                size = path.getsize(file_path)
                mtime = os.stat(file_path)[stat.ST_MTIME]
                self._add_to_file_cache_map(file_path, hash)
                self._add_to_db(db_map, dir, PhotosDbItem(name, size, mtime, hash))
                verbose_nhdr("\rfiles: %d" % len(db_map))

        verbose_nhdr("\n")

    def _add_to_file_cache_map(self, file_path, hash):
        size = path.getsize(file_path)
        mtime = os.stat(file_path)[stat.ST_MTIME]

        if self._file_cache_map.has_key(file_path):
            cache_item = self._file_cache_map[file_path]
            if cache_item.size == size and cache_item.mtime == mtime \
                    and cache_item.hash == hash:
                return

        self._file_cache_map[file_path] = CacheItem(file_path, size, mtime, hash)

    def update_db(self):
        """
        Update db with the photos root content.
        Do not cleanup old data in db.
        If there is existing file with same cache it is replaced.
        """
        verbose("Update DB")
        self._fill_db(self._photos_root, self._db_map)

        self._write_db(self._db_map, self._photos_db)

        self._write_cache(self._file_cache_map, self._file_cache)

        if self._dry_run:
            verbose("DRY RUN")

    def _add_to_db(self, db_map, root_dir, db_item):
        """
        Add item to db
        """
        debug("Add to db\n  name: %s\n  size: %d\n  hash: %s" %
              (db_item.name, db_item.size, db_item.hash))
        # check if we have this file in the db by hash
        if db_map.has_key(db_item.hash):
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

        # first create current root directory db
        rmap = {}
        self._fill_db(self._photos_root, rmap)

        values = rmap.values()
        # next remove duplicate move files
        for ritem in values:
            for dupitem in ritem.duplicate:
                verbose("Found duplicate:\n  name: %s" % (dupitem))
                self._recycle(dupitem)
            ritem.duplicate = []

        # next move files to right location according the photos root
        for ritem in values:
            if ritem.hash in self._db_map:
                ditem = self._db_map[ritem.hash]
                if ditem.size != ritem.size:
                    verbose("Size mismatch:\n  old name: %s\n  old size: %d\n  new name: %s\n  new size: %d" % (
                        ritem.name, ritem.size, ditem.name, ditem.size))
                    continue
                if ditem.name != ritem.name:
                    f1 = self._photos_root + os.sep + ritem.name
                    f2 = self._photos_root + os.sep + ditem.name
                    verbose("Move files:\n  old name: %s\n  new name: %s" % (f1, f2))
                    if path.exists(f2):
                        if _calculate_hash(f2, self._file_cache_map) == ritem.hash:
                            verbose("Found duplicate:\n  name: %s" % (ritem.name))
                            self._recycle(ritem.name)
                        else:
                            error("Destination already exist skip move:\n  file: %s:" % (f2))
                    else:
                        if not self._dry_run:
                            os.renames(f1, f2)
                            os.utime(f2, (ditem.mtime, ditem.mtime))
            else:
                f1 = self._photos_root + os.sep + ritem.name
                f2 = self._photos_root + os.sep + CHECK_DIR + os.sep + ritem.name
                verbose("Not in DB move to:\n  name: %s" % (f2))
                if path.exists(f2):
                    error("Destination already exist skip move:\n  file: %s:" % (f2))
                else:
                    if not self._dry_run:
                        os.renames(f1, f2)

        self._write_cache(self._file_cache_map, self._file_cache)

        if self._dry_run:
            verbose("DRY RUN")

    def _recycle(self, name):
        """
        Move file to local .recycle
        """
        f1 = self._photos_root + os.sep + name
        f2 = self._photos_root + os.sep + RECYCLE_DIR + os.sep + name
        i = 0
        while path.exists(f2):
            f2 = self._photos_root + os.sep + RECYCLE_DIR + os.sep + name + '_' + str(i)
            i += 1
        verbose("Recycle:\n  file: %s" % (f2))
        if not self._dry_run:
            os.renames(f1, f2)


# ========================================


def parse_args():
    """
    Parse arguments and print help message if requested.
    """
    global DRY_RUN
    global DEBUG
    global VERBOSE
    global PHOTOS_DB
    global PHOTOS_ROOT
    global UPDATE_DB
    global UPDATE_ROOT
    global FILE_CACHE

    parser = argparse.ArgumentParser(description='Script to manage photos names and directory places')
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
    parser.add_argument('--photos-db',
                        dest='photos_db',
                        default=PHOTOS_DB,
                        required=True,
                        help='point to a db file to use, default is "%s"' % (PHOTOS_DB))
    parser.add_argument('--photos-root',
                        dest='photos_root',
                        default=PHOTOS_ROOT,
                        required=True,
                        help='point to photos root dir, default is "%s"' % (PHOTOS_ROOT))
    parser.add_argument('--file-cache',
                        dest='file_cache',
                        default=FILE_CACHE,
                        required=False,
                        help='point to a file hash cache to use, default is "%s"' % (FILE_CACHE))
    parser.add_argument('--update-db',
                        dest='update_db',
                        action='store_true',
                        help='update the db with data from photos root')
    parser.add_argument('--update-root',
                        dest='update_root',
                        action='store_true',
                        help='update the photos root with data from db')

    args = parser.parse_args()

    DRY_RUN = args.dry_run
    DEBUG = args.debug
    VERBOSE = args.verbose or DEBUG
    PHOTOS_DB = args.photos_db
    PHOTOS_ROOT = args.photos_root
    UPDATE_DB = args.update_db
    UPDATE_ROOT = args.update_root
    FILE_CACHE = args.file_cache

    basedir = path.dirname(sys.argv[0])

    if len(path.dirname(PHOTOS_ROOT)) == 0:
        PHOTOS_ROOT = "%s%s%s" % (basedir, os.sep, PHOTOS_ROOT)
    if len(path.dirname(PHOTOS_DB)) == 0:
        PHOTOS_DB = "%s%s%s" % (basedir, os.sep, PHOTOS_DB)
    if len(path.dirname(FILE_CACHE)) == 0:
        FILE_CACHE = "%s%s%s" % (basedir, os.sep, FILE_CACHE)

    PHOTOS_ROOT = path.abspath(PHOTOS_ROOT)
    PHOTOS_DB = path.abspath(PHOTOS_DB)
    FILE_CACHE = path.abspath(FILE_CACHE)

    if UPDATE_DB and UPDATE_ROOT:
        error("Only one of the --update-db or --update-root should be specified.")
        sys.exit(1)

    if (not UPDATE_DB) and (not UPDATE_ROOT):
        error("One of the --update-db or --update-root should be specified.")
        sys.exit(1)


def main():
    parse_args()

    t0 = time.time()
    inst = PhotosManage(PHOTOS_DB, PHOTOS_ROOT, FILE_CACHE, DRY_RUN)
    verbose("Load DB for: %d seconds" % (time.time() - t0))

    if UPDATE_DB:
        t0 = time.time()
        inst.update_db()
        verbose("Update DB for: %d seconds" % (time.time() - t0))

    if UPDATE_ROOT:
        t0 = time.time()
        inst.update_root()
        verbose("Update root for: %d seconds" % (time.time() - t0))


# ========================================
if __name__ == '__main__':
    main()
