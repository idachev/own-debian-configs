#!/usr/bin/env python3

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
from datetime import datetime, timezone
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
elif DEFAULT_THREADS > 3:
    DEFAULT_THREADS = 3

# ========================================
# Defines

BUFF_FILE = 10 * 1024 * 1024

CHECK_DIR = ".check"
RECYCLE_DIR = ".recycle"
PARKED_DIR = ".parked"

# ========================================
# Debugging

VERBOSE = False
DEBUG = False


def time_iso():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def stdout_msg(msg):
    print(msg)
    sys.stdout.flush()
    sys.stderr.flush()


def stdout_msg_noln(msg):
    sys.stdout.write(msg)
    sys.stdout.flush()
    sys.stderr.flush()


def level_msg(level, msg):
    stdout_msg("%s [%s] %s" % (time_iso(), level, msg))


def log_verbose(msg):
    if VERBOSE:
        level_msg('INF', msg)


def log_verbose_nhdr(msg):
    if VERBOSE:
        stdout_msg_noln(msg)


def log_debug(msg):
    if DEBUG:
        level_msg('DBG', msg)


def log_error(msg):
    level_msg('ERR', msg)


# ========================================

class FilesDbItem:
    name = None
    size = 0
    mtime = 0
    hash = None
    duplicates = None

    def __init__(self, _name, _size, _mtime, _hash):
        self.name = _name
        self.size = _size
        self.mtime = _mtime
        self.hash = _hash
        self.duplicates = []


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

    It is faster compared to call external process like sha512sum
    """
    s = hashlib.sha512()

    with open(file_path, 'rb') as rfile:
        buf = rfile.read(BUFF_FILE)
        while len(buf) > 0:
            s.update(buf)
            buf = rfile.read(BUFF_FILE)

    return s.hexdigest()


def _calculate_hash(file_path, name, file_cache_map):
    """
    Calculate hash of a file
    """
    log_debug('CH: %s' % file_path)

    size = path.getsize(file_path)
    mtime = os.stat(file_path)[stat.ST_MTIME]
    res_hash = None

    if name in file_cache_map:
        cache_item = file_cache_map[name]
        if cache_item.size == size and cache_item.mtime == mtime:
            res_hash = cache_item.hash

    if res_hash is None:
        res_hash = _calculate_hash_int_hashlib(file_path)
        file_cache_map[name] = CacheItem(name, size, mtime, res_hash)

    return res_hash


def part_multiprocess_hashes(queue, part_name, root_path, files_part, file_cache_map):
    log_verbose("Start processing part: %s root_path: %s files: %d" % (part_name, root_path, len(files_part)))

    hashes = {}
    for file_path in files_part:
        name = file_path[len(root_path) + 1:]
        hashes[file_path] = _calculate_hash(file_path, name, file_cache_map)
        for i in range(1, 5):
            if len(hashes) == (i * len(files_part) / 4):
                log_verbose('Processed part: %s progress: %d%%' % (part_name, (25 * i)))
    queue.put(hashes)


def parts_multiprocess_hashes(root_path, files_parts, file_cache_map):
    processes = []

    part_i = 0
    for files_part in files_parts:
        queue = Queue()

        process = Process(
            target=part_multiprocess_hashes,
            args=(queue, part_i, root_path, files_part, file_cache_map))

        proc_data = [queue, process]
        processes.append(proc_data)

        process.start()

        part_i += 1

    files_parts_hashes = []
    for proc_data in processes:
        files_parts_hashes.append(proc_data[0].get())

    for proc_data in processes:
        proc_data[1].join()

    return files_parts_hashes


class FilesManage:
    _src_db_map = None
    _files_db = None
    _files_src_root = None
    _files_dst_root = None
    _working_dir = True
    _recycle_duplicates = False
    _dry_run = True
    _files_cache = None
    _file_cache_map = None

    def __init__(self,
                 files_db,
                 files_src_root,
                 files_dst_root,
                 files_cache,
                 working_dir,
                 recycle_duplicates=False,
                 dry_run=True):
        self._files_db = files_db
        self._files_src_root = files_src_root
        self._files_dst_root = files_dst_root
        self._files_cache = files_cache
        self._working_dir = working_dir
        self._recycle_duplicates = recycle_duplicates
        self._dry_run = dry_run

        log_verbose("files src db: %s" % self._files_db)
        log_verbose("files src root dir: %s" % self._files_src_root)
        log_verbose("files dst root dir: %s" % self._files_dst_root)
        log_verbose("files src/dst cache: %s" % self._files_cache)
        log_verbose("files working dir: %s" % self._working_dir)
        log_verbose("dry run: %d" % self._dry_run)

        self._src_db_map = self._read_db()
        self._dst_db_map = {}
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
        log_verbose("Writing DB file: %s" % file_path)
        self._write_pickle(list(db_map.values()), file_path)

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
        log_verbose("Writing file cache: %s" % file_path)
        self._write_pickle(list(file_cache_map.values()), file_path)

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
            log_verbose("File does not exist will be created: %s" % file_path)

        return pickle_data

    def _fill_db(self, root_path, db_map):
        """
        Fill DB from directory.
        """
        log_verbose("Fill db from: %s" % root_path)
        all_files = []
        for root, dirs, files in os.walk(root_path):
            files = (path.join(root, x) for x in files)
            for file_path in files:
                name = file_path[len(root_path) + 1:]
                if (os.sep + '.') in name or name.startswith('.'):
                    continue
                all_files.append(file_path)

        parts = np.array_split(all_files, DEFAULT_THREADS)
        parts_res = parts_multiprocess_hashes(root_path, parts, self._file_cache_map)

        processed = 0
        for hashes in parts_res:
            assert isinstance(hashes, dict)
            for file_path, res_hash in hashes.items():
                name = file_path[len(root_path) + 1:]
                size = path.getsize(file_path)
                mtime = os.stat(file_path)[stat.ST_MTIME]

                self._add_to_file_cache_map(file_path, name, res_hash)

                self._add_to_db(db_map, root_path, FilesDbItem(name, size, mtime, res_hash))

                log_verbose_nhdr("\rfiles: %d" % processed)
                processed += 1

        log_verbose_nhdr("\n")

    def _add_to_file_cache_map(self, file_path, name, res_hash):
        size = path.getsize(file_path)
        mtime = os.stat(file_path)[stat.ST_MTIME]

        if name in self._file_cache_map:
            cache_item = self._file_cache_map[name]
            if cache_item.size == size and cache_item.mtime == mtime \
                    and cache_item.hash == res_hash:
                return

        self._file_cache_map[name] = CacheItem(name, size, mtime, res_hash)

    def update_db(self):
        """
        Update db with the files root content.
        Do not cleanup old data in db.
        If there is existing file with same cache it is replaced.
        """
        log_verbose("Update DB")
        self._fill_db(self._files_src_root, self._src_db_map)

        self._write_db(self._src_db_map, self._files_db)

        self._write_cache(self._file_cache_map, self._files_cache)

        if self._dry_run:
            log_verbose("DRY RUN")

    def _add_to_db(self, db_map, root_dir, db_item):
        """
        Add item to db
        """
        log_debug("Add to db\n  name: %s\n  size: %d\n  hash: %s" %
                  (db_item.name, db_item.size, db_item.hash))

        if db_item.hash in db_map:
            existing_item = db_map[db_item.hash]
            if existing_item.name == db_item.name:
                return

            if path.exists(path.join(root_dir, existing_item.name)):
                if db_item.name not in [iter.name for iter in existing_item.duplicates]:
                    log_verbose_nhdr("\n")  # keep this because of files counter with \r
                    log_verbose("Found duplicates:\n  %s\n  %s" %
                                (existing_item.name, db_item.name))
                    existing_item.duplicates.append(db_item)

                return

            log_verbose("Replace none existing duplicates:\n  %s\n  %s" % (existing_item.name, db_item.name))

        db_map[db_item.hash] = db_item

    def update_root(self):
        """
        Find files which are not in the right position and move them.
        """
        log_verbose("Update root")

        if len(self._src_db_map) == 0:
            log_error("Source DB is empty")
            sys.exit(101)

        if self._files_dst_root is None:
            log_error("Destination root directory should be set")
            sys.exit(102)

        self._dst_db_map = {}
        self._fill_db(self._files_dst_root, self._dst_db_map)

        dst_items = self._dst_db_map.values()

        if self._recycle_duplicates:
            for dst_item in dst_items:
                for dup_item in dst_item.duplicates:
                    log_verbose("Found duplicate:\n  name: %s" % dup_item)
                    self._move_to_recycle(dup_item.name)
                dst_item.duplicates = []

        for dst_item in dst_items:
            if dst_item.hash not in self._src_db_map:
                self._move_for_check_item(dst_item)
                continue

            src_item = self._src_db_map[dst_item.hash]
            if src_item.size != dst_item.size:
                log_verbose("Size mismatch:\n  dst name: %s\n  dst size: %d\n  src name: %s\n  src size: %d" % (
                    dst_item.name, dst_item.size, src_item.name, src_item.size))

                self._move_for_check_item(dst_item)
                continue

            self._sync_duplicates(src_item, dst_item)

            if src_item.name == dst_item.name:
                continue

            self._safe_move_dst(dst_item.name, src_item)

        self._cleanup_cache()

        self._write_cache(self._file_cache_map, self._files_cache)

        if self._dry_run:
            log_verbose("DRY RUN")

    def _cleanup_cache(self):
        cached_items = list(self._file_cache_map.values())
        for cached_item in cached_items:
            assert isinstance(cached_item, CacheItem)
            cached_item_path = path.join(self._files_dst_root, cached_item.path)
            if not path.exists(cached_item_path):
                self._file_cache_map.pop(cached_item.path, None)

    def _move_files(self, src_file_path, dst_file_path, mtime_to_set):
        log_verbose("Move files:\n  old name: %s\n  new name: %s" % (src_file_path, dst_file_path))
        if not self._dry_run:
            os.renames(src_file_path, dst_file_path)
            os.utime(dst_file_path, (mtime_to_set, mtime_to_set))

    def _sync_duplicates(self, src_item, dst_item):
        assert isinstance(src_item, FilesDbItem)
        assert isinstance(dst_item, FilesDbItem)

        if len(dst_item.duplicates) == 0:
            return

        if len(src_item.duplicates) == 0:
            log_verbose("No source duplicates recycle destination")
            for dup_item in dst_item.duplicates:
                self._move_to_recycle(dup_item.name)

            return

        src_dup_names = [item.name for item in src_item.duplicates]
        dst_dup_names = [item.name for item in dst_item.duplicates]

        dst_dup_not_in_src = []
        for dup_item in dst_item.duplicates:
            if dup_item.name not in src_dup_names:
                dst_dup_not_in_src.append(dup_item)

        src_dup_not_in_dst = []
        for dup_item in src_item.duplicates:
            if dup_item.name not in dst_dup_names:
                src_dup_not_in_dst.append(dup_item)

        if len(src_dup_not_in_dst) == 0 or len(dst_dup_not_in_src) == 0:

            if len(dst_dup_not_in_src) != 0:
                log_verbose("All source duplicates matched, recycle rest of destination")

                for dup_item in dst_dup_not_in_src:
                    self._move_to_recycle(dup_item.name)

            return

        for i in range(0, len(dst_dup_not_in_src)):
            dst_dup_item = dst_dup_not_in_src[i]

            if i >= len(src_dup_not_in_dst):
                log_verbose("All source duplicates moved, recycle rest of destination")

                self._move_to_recycle(dst_dup_item.name)
                continue

            src_dup_item = src_dup_not_in_dst[i]

            self._safe_move_dst(dst_dup_item.name, src_dup_item)

    def _safe_move_dst(self, dst_name, src_item):
        assert isinstance(src_item, FilesDbItem)

        f1 = path.join(self._files_dst_root, dst_name)
        f2 = path.join(self._files_dst_root, src_item.name)

        if path.exists(f2):
            if _calculate_hash(f2, src_item.name, self._file_cache_map) == src_item.hash:
                log_verbose("Source name already exists and match, recycle destination")

                self._move_to_recycle(dst_name)
                return
            else:
                self._rename_diff_content_same_name(src_item.name)

        self._move_files(f1, f2, src_item.mtime)

    def _rename_diff_content_same_name(self, name):
        file_path = path.join(self._files_dst_root, name)

        res_hash = _calculate_hash(file_path, name, self._file_cache_map)

        if res_hash not in self._dst_db_map:
            self._move_to_check(name)
            return

        dst_item = self._dst_db_map[res_hash]
        new_file = self._move_to_parked(name)

        new_name = new_file[len(self._files_dst_root) + 1:]

        dst_item.name = new_name

        cache_item = self._file_cache_map[name]
        del self._file_cache_map[name]
        self._file_cache_map[new_name] = cache_item

    def _move_for_check_item(self, item):
        assert isinstance(item, FilesDbItem)

        self._move_to_check(item.name)

        if len(item.duplicates) > 0:
            for dup_item in item.duplicates:
                self._move_to_check(dup_item.name)

    def _move_to_check(self, name):
        """
        Move file to local CHECK_DIR
        """
        log_verbose("Not in DB move to check:\n  %s" % name)

        check_dir = path.join(self._files_dst_root, self._working_dir, CHECK_DIR)

        self._move_file_to_dir_inc_existing(name, self._files_dst_root, check_dir, CHECK_DIR)

        self._file_cache_map.pop(name, None)

    def _move_to_recycle(self, name):
        """
        Move file to local RECYCLE_DIR
        """
        log_verbose("Recycle:\n  %s" % name)

        recycle_dir = path.join(self._files_dst_root, self._working_dir, RECYCLE_DIR)

        self._move_file_to_dir_inc_existing(name, self._files_dst_root, recycle_dir, RECYCLE_DIR)

        self._file_cache_map.pop(name, None)

    def _move_to_parked(self, name):
        """
        Move file to local PARKED_DIR
        """
        log_verbose("Temporary parked duplicate source name file:\n  %s" % name)

        parked_dir = path.join(self._files_dst_root, self._working_dir, PARKED_DIR)

        return self._move_file_to_dir_inc_existing(name, self._files_dst_root, parked_dir, PARKED_DIR)

    def _move_file_to_dir_inc_existing(self, name, src_dir, dst_dir, context):
        f1 = path.join(src_dir, name)
        f2 = path.join(dst_dir, name)

        i = 0
        while path.exists(f2):
            f2 = path.join(dst_dir, name + context + '_' + str(i))
            i += 1

        if not self._dry_run:
            if not path.exists(dst_dir):
                os.makedirs(dst_dir)

            os.renames(f1, f2)

        return f2


# ========================================


def parse_args():
    """
    Parse arguments and print help message if requested.
    """
    global DRY_RUN
    global RECYCLE_DUPLICATES
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
    parser.add_argument('--recycle-duplicates',
                        dest="recycle_duplicates",
                        action='store_true',
                        help='recycle duplicates otherwise sync to source')
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
    RECYCLE_DUPLICATES = args.recycle_duplicates
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
        log_error("Only one of the -db/--update-db or -root/--update-root should be specified.")
        sys.exit(1)

    if (not UPDATE_DB) and (not UPDATE_ROOT):
        log_error("One of the -db/--update-db or -root/--update-root should be specified.")
        sys.exit(2)

    FILES_SRC_ROOT = path.abspath(FILES_SRC_ROOT[0])

    if FILES_DST_ROOT is not None:
        FILES_DST_ROOT = path.abspath(FILES_DST_ROOT)

    if UPDATE_DB and FILES_DST_ROOT is not None:
        log_error("Destination root directory should be not set when update DB: %s" % FILES_DST_ROOT)
        sys.exit(3)

    if UPDATE_ROOT and FILES_DST_ROOT is None:
        log_error("Destination root directory is required when update root")
        sys.exit(4)

    if not path.isdir(FILES_SRC_ROOT) or not path.exists(FILES_SRC_ROOT):
        log_error("Files source root is not a directory: %s" % FILES_SRC_ROOT)
        sys.exit(5)

    if FILES_DST_ROOT is not None and (not path.isdir(FILES_DST_ROOT) or not path.exists(FILES_DST_ROOT)):
        log_error("Files destination root is not a directory: %s" % FILES_DST_ROOT)
        sys.exit(6)

    if UPDATE_ROOT and FILES_DST_ROOT == FILES_SRC_ROOT:
        log_error("When updating root the source should be differ from destination: %s" % FILES_SRC_ROOT)
        sys.exit(7)

    if len(path.dirname(FILES_DB)) != 0:
        log_error("You cannot specify path in the files DB name: %s" % FILES_DB)
        sys.exit(8)

    if len(path.dirname(FILES_CACHE)) != 0:
        log_error("You cannot specify path in the files cache name: %s" % FILES_CACHE)
        sys.exit(9)

    if len(path.dirname(WORKING_DIR)) != 0:
        log_error("You cannot specify path in the working directory name: %s" % WORKING_DIR)
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
    inst = FilesManage(FILES_DB, FILES_SRC_ROOT, FILES_DST_ROOT, FILES_CACHE, WORKING_DIR, RECYCLE_DUPLICATES, DRY_RUN)
    log_verbose("Load DB for: %d seconds" % (timeit.default_timer() - t0))

    if UPDATE_DB:
        t0 = timeit.default_timer()
        inst.update_db()
        log_verbose("Update DB for: %d seconds" % (timeit.default_timer() - t0))
    elif UPDATE_ROOT:
        t0 = timeit.default_timer()
        inst.update_root()
        log_verbose("Update root for: %d seconds" % (timeit.default_timer() - t0))


# ========================================
if __name__ == '__main__':
    main()
