#!/bin/bash
# Shell script to backup MySql database
# To backup Nysql databases file to /backup dir and later pick up by your
# script. You can skip few databases from backup too.
# For more info please see (Installation info):
# http://www.cyberciti.biz/nixcraft/vivek/blogger/2005/01/mysql-backup-script.html
# Last updated: Aug - 2005
# --------------------------------------------------------------------
# This is a free shell script under GNU GPL version 2.0 or above
# Copyright (C) 2004, 2005 nixCraft project
# Feedback/comment/suggestions : http://cyberciti.biz/fb/
# -------------------------------------------------------------------------
# This script is part of nixCraft shell script collection (NSSC)
# Visit http://bash.cyberciti.biz/ for more information.
# -------------------------------------------------------------------------
 
MyUSER="root" # USERNAME
MyPASS="mysql12345" # PASSWORD
MyHOST="localhost" # Hostname
 
# Linux bin paths, change this if it can not be autodetected via which command
MYSQL="$(which mysql)"
MYSQLDUMP="$(which mysqldump)"
CHOWN="$(which chown)"
CHMOD="$(which chmod)"
GZIP="$(which gzip)"
 
# Backup Dest directory, change this if you have someother location
MBD="/home/idachev/personal/backup/mysql"
 
# Get hostname
HOST="$(hostname)"
 
# Get data in dd-mm-yyyy format
NOW="$(date +"%Y%m%d_%H%M%S")"
 
# File to store current backup file
FILE=""
# Store list of databases
DBS=""
 
# list of databases to backup
TOBACKUP="d6_dev_test d6_test_db_1 test_db_1 wp_test_db_1"
 
# Get all database list first
DBS="$($MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -Bse 'show databases')"

for db in $DBS; do
  backupdb=0
  if [ "$TOBACKUP" != "" ]; then
    for i in $TOBACKUP; do
      [ "$db" == "$i" ] && backupdb=1 || :
    done
  fi
 
  if [ "$backupdb" == "1" ]; then
    [ ! -d $MBD/$db ] && mkdir -p $MBD/$db || :
    FILE="$MBD/$db/$db.$HOST.$NOW.gz"
    echo "Backup to $FILE"
    $MYSQLDUMP -u $MyUSER -h $MyHOST -p$MyPASS $db | $GZIP -9 > $FILE
  fi
done

