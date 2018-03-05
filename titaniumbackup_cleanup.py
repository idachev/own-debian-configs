#!/usr/bin/env python

import logging
import os
import re
import sys
from datetime import datetime

from properties.p import Property

APP_APK_MD5 = 'app_apk_md5'

MAX_LAST_BACKUPS = 7

LOG_NAME = __file__

log = None


def create_logger(log_level=logging.INFO):
    global log

    log = logging.getLogger(LOG_NAME)
    log.setLevel(log_level)

    handlers = [logging.StreamHandler(sys.stdout)]

    if log_level < logging.INFO:
        formatter = logging.Formatter(
            "%(asctime)s [%(levelname)-5s] [%(thread)d:%(process)06d] " +
            "[%(filename)s:%(lineno)03d] [%(funcName)s] %(message)s")
    else:
        formatter = logging.Formatter("%(message)s")

    for handler in handlers:
        handler.setFormatter(formatter)
        handler.setLevel(log_level)
        log.addHandler(handler)


class BackupGroup(object):
    def __init__(self, name):
        self.name = name
        self.apks = {}
        self.times = {}
        self.time_to_apk_md5 = {}
        self.freed_size = 0
        self.kept_size = 0


def _do_cleanup(tb_dir, doit, keep_last_backups=MAX_LAST_BACKUPS):
    log.info('Keep last %d backups and cleanup: %s' % (keep_last_backups, tb_dir))

    backup_groups = _do_scan_directory(tb_dir)
    for backup_group in backup_groups.values():
        _do_cleanup_backup_group(backup_group, doit, keep_last_backups)

    total_freed = sum([backup_group.freed_size for backup_group in backup_groups.values()])
    total_kept = sum([backup_group.kept_size for backup_group in backup_groups.values()])

    log.info('\nApps and settings: %d' % len(backup_groups))
    log.info('Kept: %.3f GB' % (total_kept / 1024.0 / 1024.0 / 1024.0))
    log.info('Freed: %.3f GB' % (total_freed / 1024.0 / 1024.0 / 1024.0))

    if not doit:
        log.info('\nThis was a dry run to execute it add "doit" to the command')


def _extract_name_time(f, ext):
    m = re.search('(.*)-([0-9]{8}-[0-9]{6})\.' + ext, f)
    try:
        return m.group(1), datetime.strptime(m.group(2), '%Y%m%d-%H%M%S')
    except:
        return None, None


def _extract_name_md5(f):
    m = re.search('(.*)-([0-9a-z]+)\.apk\.gz', f)
    try:
        return m.group(1), m.group(2)
    except:
        return None, None


def _get_apk_md5_from_properties(fp):
    prop = Property()
    dic_prop = prop.load_property_files(fp)
    if APP_APK_MD5 in dic_prop:
        return dic_prop[APP_APK_MD5]
    else:
        return None


def _do_scan_directory(tb_dir):
    backup_groups = {}

    def get_group(name):
        if name not in backup_groups:
            backup_group = BackupGroup(name)
            backup_groups[name] = backup_group
        else:
            backup_group = backup_groups[name]
        return backup_group

    def check_append(f, fp, ext):
        name, time = _extract_name_time(f, ext)
        if not name or not time:
            log.error('Cannot parse %s name: %s' % (ext, f))
            return

        backup_group = get_group(name)
        if time not in backup_group.times:
            backup_group.times[time] = []
        backup_group.times[time].append(fp)

        log.debug('Add %s name: %s time: %s' % (ext, name, time))

        if ext == 'properties':
            md5 = _get_apk_md5_from_properties(fp)
            if not md5 and not name.startswith('com.keramidas.virtual'):
                log.warn('Failed to get md5 from properties file: %s' % fp)
            else:
                backup_group.time_to_apk_md5[time] = md5

    EXT_TO_CHECK = ['properties', 'tar.gz', 'xml.gz']

    for f in os.listdir(tb_dir):
        fp = os.path.join(tb_dir, f)
        found = False
        for ext in EXT_TO_CHECK:
            if f.endswith('.' + ext):
                check_append(f, fp, ext)
                found = True
                break

        if found:
            continue

        if f.endswith('.apk.gz'):
            name, md5 = _extract_name_md5(f)
            if not name or not md5:
                log.error('Cannot parse apk name: %s' % f)
                continue

            log.debug('Add name: %s apk md5: %s' % (name, md5))
            backup_group = get_group(name)
            backup_group.apks[md5] = fp
        else:
            log.warn('Unknown file: %s' % f)

    return backup_groups


def _do_cleanup_backup_group(backup_group, doit, keep_last_backups):
    assert isinstance(backup_group, BackupGroup)

    time_keys = sorted(backup_group.times.keys(), reverse=True)
    to_keep = keep_last_backups if keep_last_backups < len(time_keys) else len(time_keys)

    keep_times = time_keys[0: to_keep]
    remove_times = time_keys[to_keep:]

    backup_group.freed_size = 0

    keep_apk_md5s = []
    for check_time in keep_times:
        to_keep = backup_group.times[check_time]
        for fp in to_keep:
            backup_group.kept_size += os.path.getsize(fp)
            log.debug('Keep %s' % fp)
        if check_time in backup_group.time_to_apk_md5:
            keep_apk_md5s.append(backup_group.time_to_apk_md5[check_time])

    for remove_time in remove_times:
        to_remove = backup_group.times[remove_time]
        for fp in to_remove:
            backup_group.freed_size += os.path.getsize(fp)
            log.debug('Delete %s' % fp)
            if doit:
                os.remove(fp)

    for md5 in backup_group.apks:
        fp = backup_group.apks[md5]
        if md5 not in keep_apk_md5s:
            backup_group.freed_size += os.path.getsize(fp)
            log.debug('Delete %s' % fp)
            if doit:
                os.remove(fp)
        else:
            backup_group.kept_size += os.path.getsize(fp)
            log.debug('Keep %s' % fp)


def print_usage():
    print('Usage %s [-d] [-k=N] [doit] directory' % os.path.basename(sys.argv[0]))
    print('  -d           optional, add this to enable debug messages')
    print('  -k=N         optional, keep last N backups, default %d' % MAX_LAST_BACKUPS)
    print('  doit         optional, add this to execute deletes, otherwise it will print only preview')
    print('  directory    TitaniumBackup directory')


def main():
    log_level = logging.INFO
    keep_last_backups = MAX_LAST_BACKUPS
    doit = False
    tb_dir = None

    for i in range(1, len(sys.argv)):
        arg = sys.argv[i]
        if arg == '-d':
            log_level = logging.DEBUG
        elif arg.startswith('-k='):
            try:
                keep_last_backups = int(arg[3:])
            except ValueError:
                print('Invalid keep last N backups: %s' % arg)
                print_usage()
                sys.exit(3)
        elif arg == 'doit':
            doit = True
        elif os.path.isdir(arg):
            tb_dir = arg
        else:
            print('Unexpected or invalid argument: %s' % arg)
            print_usage()
            sys.exit(2)

    if not tb_dir:
        print_usage()
        sys.exit(1)

    create_logger(log_level)
    _do_cleanup(tb_dir, doit, keep_last_backups)


if __name__ == '__main__':
    main()
