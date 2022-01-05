#!/usr/bin/env python3

# ========================================
# Imports

import argparse
import hashlib
import os
import pickle
import stat
import sys
import timeit
from datetime import datetime, timezone
from multiprocessing import Queue, Process
from os import path

import numpy as np

# ========================================
# Settings

DRY_RUN = True

UPDATE_DB = False

DELETE_FILES = False

FILES_ROOT = "files"

DELETED_FILES_DB = "deleted_files.db"

DEFAULT_THREADS = 1

TO_DELETE_DIR = '.to-delete'

# ========================================
# Defines

BUFF_FILE = 10 * 1024 * 1024

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

    def __init__(self, _name, _size, _mtime, _hash):
        self.name = _name
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


def _calculate_hash(file_path):
    """
    Calculate hash of a file
    """
    log_debug('CH: %s' % file_path)

    res_hash = None

    if res_hash is None:
        res_hash = _calculate_hash_int_hashlib(file_path)

    return res_hash


def part_multiprocess_hashes(queue, part_name, root_path, files_part):
    log_verbose("Start processing part: %s root_path: %s files: %d" % (part_name, root_path, len(files_part)))

    hashes = {}
    for file_path in files_part:
        hashes[file_path] = _calculate_hash(file_path)

    queue.put(hashes)


def parts_multiprocess_hashes(root_path, files_parts):
    processes = []

    part_i = 0
    for files_part in files_parts:
        queue = Queue()

        process = Process(
            target=part_multiprocess_hashes,
            args=(queue, part_i, root_path, files_part))

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


class DeletedFilesManage:
    _deleted_files_db = None
    _files_root = None
    _files_cache = None
    _file_cache_map = None

    def __init__(self,
                 deleted_files_db,
                 files_root,
                 dry_run=True):
        self._deleted_files_db = deleted_files_db
        self._files_root = files_root
        self._dry_run = dry_run

        log_verbose("deleted files db: %s" % self._deleted_files_db)
        log_verbose("files root dir: %s" % self._files_root)
        log_verbose("dry run: %d" % self._dry_run)

        self._deleted_db_map = self._read_db()
        self._to_delete_db_map = {}

        self._files_for_delete_dir = path.join(self._files_root, TO_DELETE_DIR)

    def _read_db(self):
        """
        Parse our DB file.
        """
        data = self._read_pickle(self._deleted_files_db)

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
        parts_res = parts_multiprocess_hashes(root_path, parts)

        processed = 0
        for hashes in parts_res:
            assert isinstance(hashes, dict)
            for file_path, res_hash in hashes.items():
                name = file_path[len(root_path) + 1:]
                size = path.getsize(file_path)
                mtime = os.stat(file_path)[stat.ST_MTIME]

                self._add_to_db(db_map, FilesDbItem(name, size, mtime, res_hash))

                log_verbose_nhdr("\rfiles: %d" % processed)
                processed += 1

        log_verbose_nhdr("\n")

    def update_db(self):
        """
        Update db with the files root content.
        Do not cleanup old data in db.
        If there is existing file with same cache it is replaced.
        """
        log_verbose("Update DB")

        self._fill_db(self._files_root, self._deleted_db_map)

        log_verbose("Total DB files: %d" % len(self._deleted_db_map))

        if self._dry_run:
            log_verbose("DRY RUN")

            return

        self._write_db(self._deleted_db_map, self._deleted_files_db)


    def _add_to_db(self, db_map, db_item):
        """
        Add item to db
        """
        log_debug("Add to db\n  name: %s\n  size: %d\n  hash: %s" %
                  (db_item.name, db_item.size, db_item.hash))

        db_map[db_item.hash] = db_item

    def mark_delete_files(self):
        """
        Find files that need to be deleted and report them
        """
        log_verbose("Delete files")

        if len(self._deleted_db_map) == 0:
            log_error("Deleted files DB is empty")
            sys.exit(101)

        if self._files_root is None:
            log_error("Root directory should be set")
            sys.exit(102)

        self._to_delete_db_map = {}
        self._fill_db(self._files_root, self._to_delete_db_map)

        dst_items = self._to_delete_db_map.values()

        deleted_files_count = 0
        for dst_item in dst_items:
            if dst_item.hash not in self._deleted_db_map:
                continue

            src_item = self._deleted_db_map[dst_item.hash]
            if src_item.size != dst_item.size:
                log_verbose("Size mismatch:\n  dst name: %s\n  dst size: %d\n  src name: %s\n  src size: %d" % (
                    dst_item.name, dst_item.size, src_item.name, src_item.size))
                continue

            deleted_files_count += 1

            to_delete_path = self._move_file_to_dir_inc_existing(dst_item.name, self._files_root, self._files_for_delete_dir)
            log_verbose("Move for deleting: %s" % to_delete_path)

        if self._dry_run:
            log_verbose("DRY RUN")

        log_verbose("Deleted files: %d" % deleted_files_count)

    def _move_file_to_dir_inc_existing(self, name, src_dir, dst_dir):
        f1 = path.join(src_dir, name)
        f2 = path.join(dst_dir, name)

        i = 0
        while path.exists(f2):
            f2 = path.join(dst_dir, name + '_' + str(i))
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
    global UPDATE_DB
    global DELETE_FILES 
    global DEBUG
    global VERBOSE
    global FILES_ROOT
    global DELETED_FILES_DB
    global DEFAULT_THREADS

    parser = argparse.ArgumentParser(description='Script to manage files names and directory places')
    parser.add_argument('files_root', metavar='FILES_ROOT', nargs=1,
                        help='point to files root path that will be deleted')
    parser.add_argument('-q', '--quiet',
                        dest="quiet",
                        action='store_true',
                        help='quiet messages')
    parser.add_argument('-v', '--debug',
                        dest="debug",
                        action='store_true',
                        help='debug messages')
    parser.add_argument('-n', '--dry-run',
                        dest="dry_run",
                        action='store_true',
                        help='dry run')
    parser.add_argument('--deleted-files-db',
                        dest='deleted_files_db',
                        default=DELETED_FILES_DB,
                        help='file name of the deleted files DB to use, default is "%s"' % DELETED_FILES_DB)
    parser.add_argument('-db', '--update-db',
                        dest='update_db',
                        action='store_true',
                        help='update the db with data from files root')
    parser.add_argument('-del', '--delete-files',
                        dest='delete_files',
                        action='store_true',
                        help='delete the files root with data from db')

    args = parser.parse_args()

    DRY_RUN = args.dry_run
    DEBUG = (not args.quiet) and args.debug
    VERBOSE = (not args.quiet) or DEBUG
    DELETED_FILES_DB = args.deleted_files_db
    FILES_ROOT = args.files_root
    UPDATE_DB = args.update_db
    DELETE_FILES = args.delete_files

    if UPDATE_DB and DELETE_FILES:
        log_error("Only one of the -db/--update-db or -del/--delete-files should be specified.")
        sys.exit(1)

    if (not UPDATE_DB) and (not DELETE_FILES):
        log_error("One of the -db/--update-db or -del/--delete-files should be specified.")
        sys.exit(2)

    FILES_ROOT = path.abspath(FILES_ROOT[0])
    DELETED_FILES_DB = path.abspath(os.path.expanduser(DELETED_FILES_DB))

    if not path.isdir(FILES_ROOT) or not path.exists(FILES_ROOT):
        log_error("Files root is not a directory: %s" % FILES_ROOT)
        sys.exit(3)

    if DELETE_FILES and not path.exists(DELETED_FILES_DB):
        log_error("Deleted files DB does not exists: %s" % DELETED_FILES_DB)
        sys.exit(4)


def main():
    parse_args()

    t0 = timeit.default_timer()
    inst = DeletedFilesManage(DELETED_FILES_DB, FILES_ROOT, DRY_RUN)
    log_verbose("Load DB for: %d seconds" % (timeit.default_timer() - t0))

    if UPDATE_DB:
        t0 = timeit.default_timer()
        inst.update_db()
        log_verbose("Updated DB for: %d seconds" % (timeit.default_timer() - t0))
    elif DELETE_FILES:
        t0 = timeit.default_timer()
        inst.delete_files()
        log_verbose("Deleted files from root for: %d seconds" % (timeit.default_timer() - t0))


# ========================================
if __name__ == '__main__':
    main()
