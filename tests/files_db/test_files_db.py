#!/usr/bin/env python3

# ========================================
# Imports
import os
import subprocess
import sys
import tempfile
import unittest
from os import path

BASE_PATH = path.dirname(__file__)
FILES_DB_PATH = path.abspath(path.join(path.dirname(__file__), "..", "..", "files_db.py"))

if not path.exists(FILES_DB_PATH):
    raise Exception("Expecting: %s" % FILES_DB_PATH)

sys.path.append(path.normpath(FILES_DB_PATH))

import files_db
from files_db import FilesManage, WORKING_DIR, FILES_DB, FILES_CACHE


def exec_shell_cmd(exec_cmd):
    proc = subprocess.Popen(exec_cmd,
                            stdout=subprocess.PIPE,
                            shell=True,
                            universal_newlines=True)
    stdout = ""
    while proc.poll() is None:
        pc = proc.communicate()
        stdout += pc[0]

    exit_code = proc.poll()
    return [exit_code, stdout]


class TestStringMethods(unittest.TestCase):

    def test_files_db_with_duplicates(self):
        with tempfile.TemporaryDirectory(prefix="files_db_test_") as tmp_dirname:
            print("Using temporary directory: %s" % tmp_dirname)

            self.do_tests(tmp_dirname, recycle_duplicates=False)

    def test_files_db_without_duplicates(self):
        with tempfile.TemporaryDirectory(prefix="files_db_test_") as tmp_dirname:
            print("Using temporary directory: %s" % tmp_dirname)

            self.do_tests(tmp_dirname, recycle_duplicates=True)

    def test_files_db_dry_run_with_duplicates(self):
        with tempfile.TemporaryDirectory(prefix="files_db_test_") as tmp_dirname:
            print("Using temporary directory: %s" % tmp_dirname)

            self._do_test_dry_run(tmp_dirname, recycle_duplicates=False)

    def test_files_db_dry_run_without_duplicates(self):
        with tempfile.TemporaryDirectory(prefix="files_db_test_") as tmp_dirname:
            print("Using temporary directory: %s" % tmp_dirname)

            self._do_test_dry_run(tmp_dirname, recycle_duplicates=True)

    def _do_test_dry_run(self, tmp_dirname, recycle_duplicates=False):
        test_dst_org = path.join(BASE_PATH, "test_dst")
        exec_shell_cmd("cp -a %s %s" % (test_dst_org, tmp_dirname))

        test_src_org = path.join(BASE_PATH, "test_src")
        exec_shell_cmd("cp -a %s %s" % (test_src_org, tmp_dirname))

        test_dst = path.join(tmp_dirname, "test_dst")
        test_src = path.join(tmp_dirname, "test_src")

        files_db.VERBOSE = True

        files_manage = FilesManage(
            path.abspath(path.join(test_src, WORKING_DIR, FILES_DB)),
            test_src,
            test_src,
            path.abspath(path.join(test_src, WORKING_DIR, FILES_CACHE)),
            WORKING_DIR,
            recycle_duplicates=recycle_duplicates,
            dry_run=False
        )
        files_manage.update_db()

        # test again should read cache
        files_manage.update_db()

        files_manage = FilesManage(
            path.abspath(path.join(test_src, WORKING_DIR, FILES_DB)),
            test_src,
            test_dst,
            path.abspath(path.join(test_dst, WORKING_DIR, FILES_CACHE)),
            WORKING_DIR,
            recycle_duplicates=recycle_duplicates,
            dry_run=True
        )
        files_manage.update_root()

        dst_dir_content = self.get_dir_content_for_assert(test_dst)

        self.assertEqual([
            'd1/d1_1/d1_1_f1.txt: plain file',
            'd1_1/d1_1_f1.txt: file in d1/d1_1',
            'd1_1/d2/d2_f1.txt: file in directory d2',
            'd2/d1_1_f1.txt: file in d1/d1_1',
            'd2/d2_f1.txt: file in directory d2',
            'd2/d2_f2.txt: file in d2 f2 diff',
            'd2/d2_f3_g5.txt: f3 in d2',
            'd2/d2_f4.txt: d2_f4.txt',
            'd3/d3_f1.txt: d3 f1 not existing file in source'
        ], dst_dir_content)

    def do_tests(self, tmp_dirname, recycle_duplicates=False):
        test_dst_org = path.join(BASE_PATH, "test_dst")
        exec_shell_cmd("cp -a %s %s" % (test_dst_org, tmp_dirname))

        test_src_org = path.join(BASE_PATH, "test_src")
        exec_shell_cmd("cp -a %s %s" % (test_src_org, tmp_dirname))

        test_dst = path.join(tmp_dirname, "test_dst")
        test_src = path.join(tmp_dirname, "test_src")

        files_db.VERBOSE = True

        files_manage = FilesManage(
            path.abspath(path.join(test_src, WORKING_DIR, FILES_DB)),
            test_src,
            test_src,
            path.abspath(path.join(test_src, WORKING_DIR, FILES_CACHE)),
            WORKING_DIR,
            recycle_duplicates=recycle_duplicates,
            dry_run=False
        )
        files_manage.update_db()

        # test again should read cache
        files_manage.update_db()

        files_manage = FilesManage(
            path.abspath(path.join(test_src, WORKING_DIR, FILES_DB)),
            test_src,
            test_dst,
            path.abspath(path.join(test_dst, WORKING_DIR, FILES_CACHE)),
            WORKING_DIR,
            recycle_duplicates=recycle_duplicates,
            dry_run=False
        )
        files_manage.update_root()

        self._assert_dst_dir_content(test_dst, recycle_duplicates)

        # test again should not change

        files_manage.update_root()

        self._assert_dst_dir_content(test_dst, recycle_duplicates)

        # test again read cached files from destination

        files_manage = FilesManage(
            path.abspath(path.join(test_src, WORKING_DIR, FILES_DB)),
            test_src,
            test_dst,
            path.abspath(path.join(test_dst, WORKING_DIR, FILES_CACHE)),
            WORKING_DIR,
            recycle_duplicates=recycle_duplicates,
            dry_run=False
        )
        files_manage.update_root()

        self._assert_dst_dir_content(test_dst, recycle_duplicates)

    def get_dir_content_for_assert(self, root_path):
        all_files = []
        for root, dirs, files in os.walk(root_path):
            files = (path.join(root, x) for x in files)
            for file_path in files:
                all_files.append(file_path)

        res = []
        for iter_file in all_files:
            name = iter_file[len(root_path) + 1:]
            if name[-4:] == ".txt":
                with open(iter_file, 'r') as fobj:
                    content = fobj.read().replace('\n', '|')
            elif name.find("_bak") > 0:
                continue
            else:
                content = "<bin>"
            res.append("%s: %s" % (name, content))

        res.sort()
        return res

    def _assert_dst_dir_content(self, test_dst, recycle_duplicates):
        dst_dir_content = self.get_dir_content_for_assert(test_dst)

        if recycle_duplicates:
            self.assertEqual([
                '.working/.check/d2/d2_f2.txt: file in d2 f2 diff',
                '.working/.check/d3/d3_f1.txt: d3 f1 not existing file in source',
                '.working/.files_cache: <bin>',
                '.working/.recycle/d2/d1_1_f1.txt: file in d1/d1_1',
                '.working/.recycle/d2/d2_f1.txt: file in directory d2',
                'd1_1_f1_dup.txt: file in d1/d1_1',
                'd2/d2_f1.txt: file in directory d2',
                'd2/d2_f3.txt: f3 in d2',
                'd2/d2_f4.txt: d2_f4.txt',
                'f1.txt: plain file'
            ], dst_dir_content)
        else:
            self.assertEqual([
                '.working/.check/d2/d2_f2.txt: file in d2 f2 diff',
                '.working/.check/d3/d3_f1.txt: d3 f1 not existing file in source',
                '.working/.files_cache: <bin>',
                '.working/.recycle/d2/d2_f1.txt: file in directory d2',
                'd1/d1_1/d1_1_f1.txt: file in d1/d1_1',
                'd1_1_f1_dup.txt: file in d1/d1_1',
                'd2/d2_f1.txt: file in directory d2',
                'd2/d2_f3.txt: f3 in d2',
                'd2/d2_f4.txt: d2_f4.txt',
                'f1.txt: plain file'
            ], dst_dir_content)


if __name__ == '__main__':
    unittest.main()
