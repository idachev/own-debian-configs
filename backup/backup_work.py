#!/usr/bin/env python

import sys
import os
import argparse
import subprocess
import tempfile
import logging
from datetime import datetime
from threading import Thread

# ========================================
# Settings

ENCFS_ENCDEC = "/home/idachev/bin/backup/encfs_encdec.sh"

RSYNC = "rsync"

# --archive not using here to not transfer groups
RSYNC_ARGS = "--update --delete -rlptoD --partial --numeric-ids --hard-links --human-readable --one-file-system -F"

INC_RSYNC = "inc-rsync"

BACKUP_SRC_LIST_FILE = None
BACKUP_DST_LIST_FILE = None

# Use INC_RSYNC and make inceremental backup
BACKUP_INC     = "inc"
# Use INC_RSYNC and make inceremental backup
BACKUP_FULL    = "full"
# Use RSYNC and make oneshot full backup
BACKUP_ONESHOT = "oneshot"

# Default backup type is inc
BACKUP_TYPE = BACKUP_INC

ENCRYPTION = False

DRY_RUN = False

# ========================================
# Debugging

log = None

DEFAULT_LEVEL = 'error'

LOG_LEVEL = DEFAULT_LEVEL
LOG_FILE = None

log_levels = {
    'critical' : logging.CRITICAL,
    'error' : logging.ERROR,
    'warning' : logging.WARNING,
    'info' : logging.INFO,
    'debug' : logging.DEBUG,
    }

'''
Create logger
'''
def create_logger():
    global log
    log = logging.getLogger('BACKUP')
    log.setLevel(1);
    handler = logging.StreamHandler(sys.stdout);
    formatter = logging.Formatter('[%(levelname)s] %(message)s');
    handler.setFormatter(formatter)
    handler.setLevel(log_levels.get(LOG_LEVEL, DEFAULT_LEVEL))
    log.addHandler(handler)

    if LOG_FILE:
        handler = logging.FileHandler(LOG_FILE);
        formatter = logging.Formatter('[%(levelname)s] %(filename)s:%(lineno)d --> %(module)s::%(funcName)s - %(message)s');
        handler.setFormatter(formatter)
        handler.setLevel(1)
        log.addHandler(handler)

    log.debug("\n\n\n\n\nNew instance (%d)", os.getpid() )

'''
Redirect proc output to log
'''
def read_proc_output(proc, name, level):
    log.debug('Start polling for %s', name)

    out = proc.stdout
    err = proc.stderr
    out_buff = []
    err_buff = []

    def read_pipe(t, proc, pipe, level, buff):
        while True:
            try:
                line = pipe.readline()
                if not line or len(line) == 0:
                    break
                log.log(level, '[%s][%s]\t%s', proc, t, line.rstrip())
                buff.append(line)
            except:
                pass

    stderr_thread = Thread(target = read_pipe,
                           args = ('stderr', name, err, logging.DEBUG, err_buff))
    stdout_thread = Thread(target = read_pipe,
                           args = ('stdout', name, out, logging.DEBUG, out_buff))
    stderr_thread.start()
    stdout_thread.start()
    stdout_thread.join()
    stderr_thread.join()
    proc.wait()
    return ''.join(iter(out_buff)), ''.join(iter(err_buff))

# ========================================

'''
Read lines from file.
'''
def read_lines(file):
    lines = []
    with open(file, 'r') as f:
        for line in f:
            line = line.strip()
            if len(line) > 0 and (not line.startswith("#")):
                lines.append(line)

    return lines

'''
Used to get all stdoutput from executed command.
Retun tuplet with exit_code and stdout.
'''
def exec_shell_cmd(exec_cmd):
    proc = subprocess.Popen(exec_cmd, stdout=subprocess.PIPE, shell=True)
    stdout = ""
    while proc.poll() is None:
        pc = proc.communicate()
        stdout += pc[0]

    exit_code = proc.poll()
    return [exit_code, stdout]

'''
Do encryption, returns [encrypted directory, unmount bash script].
'''
def do_encryption(src):
    src_enc = tempfile.mkdtemp()
    if not src_enc.endswith(os.path.sep):
        src_enc = src_enc + os.path.sep

    exec_cmd = "%s -q -enc %s %s" % (ENCFS_ENCDEC, src, src_enc)
    [exit_code, stdout] = exec_shell_cmd(exec_cmd)
    if exit_code != 0:
        log.error("Failed to execute encfs, error: %d script: %s" % (exit_code, ENCFS_ENCDEC))
        return [None, None]
    else:
        stdout = stdout.strip()
        log.info("Encryption unmount script: %s" % stdout)
        return [src_enc, stdout]

'''
Check if the source line starts with -enc or --encryption
'''
def parse_local_encryption(src):
    LOCAL_ENCRYPTION = False
    if src.startswith("-enc "):
        src = src[5:].strip()
        LOCAL_ENCRYPTION = True
    if src.startswith("--enc "):
        src = src[6:].strip()
        LOCAL_ENCRYPTION = True
    if src.startswith("--encryption "):
        src = src[13:].strip()
        LOCAL_ENCRYPTION = True

    return LOCAL_ENCRYPTION, src

'''
Check if the destination line starts with one of:
  --type=full
  --backup_type=inc
  --backup_type=oneshot
'''
def parse_local_backup_type(dst):
    LOCAL_BACKUP_TYPE = None

    check = "--backup-type=%s " % BACKUP_FULL
    if dst.startswith(check):
        dst = dst[len(check):].strip()
        LOCAL_BACKUP_TYPE = BACKUP_FULL

    check = "--backup-type=%s " % BACKUP_INC
    if dst.startswith(check):
        dst = dst[len(check):].strip()
        LOCAL_BACKUP_TYPE = BACKUP_INC

    check = "--backup-type=%s " % BACKUP_ONESHOT
    if dst.startswith(check):
        dst = dst[len(check):].strip()
        LOCAL_BACKUP_TYPE = BACKUP_ONESHOT

    return LOCAL_BACKUP_TYPE, dst

'''
Do backup method.
'''
def do_backup(src_list, dst_list):
    if (ENCRYPTION):
        log.info("Do encryption for all.")

    log.info("")

    for src in src_list:
        LOCAL_ENCRYPTION, src = parse_local_encryption(src)

        src_name = os.path.basename(src)
        if not src.endswith(os.path.sep):
            src = src + os.path.sep
        log.info("======================================================================")
        log.info("Backup src: %s" % (src))
        log.info("      name: %s" % (src_name))
        log.info("encryption: %d" % (ENCRYPTION or LOCAL_ENCRYPTION))

        if not os.path.exists(src):
            log.error("Source path does not exist: %s" % (src))
            continue

        unmount_script = None
        if (ENCRYPTION or LOCAL_ENCRYPTION) and (not DRY_RUN):
            [src_enc, unmount_script] = do_encryption(src)
            if src_enc == None:
                continue
            src = src_enc

        log.info("")

        for dst in dst_list:
            LOCAL_BACKUP_TYPE, dst = parse_local_backup_type(dst)
            if LOCAL_BACKUP_TYPE:
                backup_type = LOCAL_BACKUP_TYPE
            else:
                backup_type = BACKUP_TYPE
            log.info("Do backup type: %s" % backup_type)

            if not dst.endswith(os.path.sep):
                dst = dst + os.path.sep
            dst = dst + src_name
            log.info("Backup dst: %s" % (dst))

            if backup_type == BACKUP_FULL or backup_type == BACKUP_INC:
                dbg_args = "-d %s" % LOG_LEVEL

                cmd_args = "inc"
                if backup_type == BACKUP_FULL:
                    cmd_args = "full"

                exec_cmd = "%s %s %s %s %s" % (INC_RSYNC, dbg_args, cmd_args, src, dst)
                exec_name = 'inc-rsync'
            else:
                dbg_args = ""
                if log.isEnabledFor(logging.DEBUG):
                    dbg_args = "-v --itemize-changes"
                elif log.isEnabledFor(logging.INFO):
                    dbg_args = "-v "

                if not src.endswith(os.path.sep):
                    src = src + os.path.sep
                if not dst.endswith(os.path.sep):
                    dst = dst + os.path.sep

                cmd_args = "--update --delete --archive --partial --numeric-ids --hard-links --human-readable --one-file-system -F"

                exec_cmd = "%s %s %s %s %s" % (RSYNC, dbg_args, cmd_args, src, dst)
                exec_name = 'rsync'

            log.info("========================================")
            log.info("Invoke %s" % exec_cmd)
            if not DRY_RUN:
                proc = subprocess.Popen(exec_cmd, 
                                        shell = True,
                                        bufsize = 512,
                                        stdout = subprocess.PIPE,
                                        stdin = subprocess.PIPE,
                                        stderr = subprocess.PIPE)
                procLog = logging.DEBUG
                if not log.isEnabledFor(logging.DEBUG):
                    procLog = logging.INFO

                log.info("========================================")
                out, err = read_proc_output(proc, exec_name, procLog)
                log.info("========================================")
                log.info("")

                exit_code = proc.poll()
                if exit_code != 0:
                    log.error("Failed to execute backup, error: %d" % (exit_code))
            else:
                log.info("(DRY RUN)")

            log.info("")

        if unmount_script != None:
            exec_shell_cmd("/bin/sh %s" % unmount_script)

'''
Parse arguments and print help message if requested.
'''
def parse_args():
    global DRY_RUN
    global LOG_LEVEL
    global LOG_FILE
    global BACKUP_TYPE
    global BACKUP_SRC_LIST_FILE
    global BACKUP_DST_LIST_FILE
    global RSYNC
    global INC_RSYNC
    global ENCRYPTION

    parser = argparse.ArgumentParser(description='Script to backup list of directories using inc-rsync')
    parser.add_argument('-d', '--debug',
                        dest = 'log_level',
                        metavar = 'LEVEL',
                        default = DEFAULT_LEVEL,
                        choices = ('error', 'warning', 'info', 'debug'),
                        help ='Controls how much information will be printed on the console. LEVEL may be one of error, warning, info or debug. Default is error')

    parser.add_argument('-l', '--log-file',
                        dest = 'log_file',
                        metavar = 'FILE',
                        help = 'Outputs debug information to FILE.')

    parser.add_argument('-n', '--dry-run',
                        dest = 'dry_run',
                        action = 'store_true',
                        help = 'dry run')

    parser.add_argument('--backup-type',
                        dest = 'backup_type',
                        metavar = 'TYPE',
                        default = BACKUP_INC,
                        choices = (BACKUP_FULL, BACKUP_INC, BACKUP_ONESHOT),
                        help = \
"""
Type of the backup to perform.
"%s" - do full backup, using inc-rsync.
"%s" - do inc backup, using inc-rsync, default one.
"%s" - do one time full backup, using rsync
""" % (BACKUP_FULL, BACKUP_INC, BACKUP_ONESHOT))
    parser.add_argument('--src-list',
                        dest = 'src_list',
                        required = True,
                        help = 'point to file with list of source directories to backup')

    parser.add_argument('--dst-list',
                        dest = 'dst_list',
                        required = True,
                        help = 'point to file with list of destinations to backup to')

    parser.add_argument('--inc-rsync',
                        dest = 'inc_rsync',
                        default = INC_RSYNC,
                        help = 'point to inc-rsync script, default is "%s"' % (INC_RSYNC))

    parser.add_argument('--rsync',
                        dest = 'rsync',
                        default = RSYNC,
                        help = 'point to rsync script, default is "%s"' % (RSYNC))

    parser.add_argument('-enc', '--encryption',
                        dest = 'enc',
                        action = 'store_true',
                        help = 'do encryption, using custom script: %s' % ENCFS_ENCDEC)

    args = parser.parse_args()

    LOG_LEVEL = args.log_level
    LOG_FILE = args.log_file
    DRY_RUN = args.dry_run
    BACKUP_TYPE = args.backup_type
    BACKUP_SRC_LIST_FILE = args.src_list
    BACKUP_DST_LIST_FILE = args.dst_list
    INC_RSYNC = args.inc_rsync
    RSYNC = args.rsync
    ENCRYPTION = args.enc

'''
Main method.
'''
def main():
    parse_args()
    create_logger()

    log.debug("src list: %s" % (BACKUP_SRC_LIST_FILE))
    src_list = read_lines(BACKUP_SRC_LIST_FILE)
    log.debug(src_list)
    log.debug("")

    log.debug("dst list: %s" % (BACKUP_DST_LIST_FILE))
    dst_list = read_lines(BACKUP_DST_LIST_FILE)
    log.debug(dst_list)
    log.debug("")

    do_backup(src_list, dst_list)

    log.info("======================================================================")
    log.info("DONE")

# ========================================
main()

