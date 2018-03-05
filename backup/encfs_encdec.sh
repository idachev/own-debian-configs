#!/bin/bash

# This script is used to mount a directory with encfs for encryption or
# decription with four keys. The password should be in the same direcotry
# as the script along with the encfs key config files.
#
# The taregt driecotry could be used to directlly copy the enc/dec files.
# The script also generates a temporary script file to unmount all levels
# of encription directory created.

ENCFS='/usr/bin/encfs'

print_usage()
{
	echo -e "Usage $0"
	echo -e "\t-enc <source dir> <target dir>\t- to mount the source as encripted to target"
	echo -e "\t-dec <source dir> <target dir>\t- to mount the source as decrypted to target"
  echo -e ""
  echo -e "Optional aguments:"
	echo -e "\t-q \t- do it quiet only dump the unmount script."
	echo -e ""
	echo -e "The target directory should exist and should be empty one."
}

if [ $# -eq 0 ]; then
  print_usage
  exit 1
fi

ENC_DEC=0
QUIET=0

while (( "$#" )); do
  if [ $1 = "-enc" ]; then
	  ENC_DEC=1
  elif [ $1 = "-dec" ]; then
	  ENC_DEC=2
  elif [ $1 = "-q" ]; then
	  QUIET=1
  elif [[ $1 = -* ]]; then
	  echo "Unknown argument: $1"
  	print_usage
	  exit 2
  else
    break
  fi

  shift
done

if [ $ENC_DEC -eq 0 ]; then
	echo "Expected -enc or -dec argument!"
	print_usage
	exit 3
fi

SOURCE=$1
if [ ! -d $SOURCE ]; then
	echo "Expected source to be existing directory!"
	print_usage
	exit 4
fi

TARGET=$2
if [ ! -d $TARGET ]; then
	echo "Expected target to be existing directory!"
	print_usage
	exit 5
fi

BASEDIR=$(dirname $0)

# Gen temp dirs
TARGET1="$(mktemp -d --suffix .encfs)"
TARGET2="$(mktemp -d --suffix .encfs)"
TARGET3="$(mktemp -d --suffix .encfs)"
TARGET4=$TARGET

# Used for encryption
# Usage mount_encfs "level0.xml" "password" SOURCE TARGET
function mount_encfs() {
	export ENCFS6_CONFIG="$1"
	echo "$2" | $ENCFS -S --reverse "$3" "$4"
	[ $? -eq 0 ] || echo "Mount $3 on $4 failed err: $?"
  if [ $QUIET -ne 1 ]; then
  	echo "encfs return: $? - $3 on $4"
  fi
}
# Used for decription
function mount_decfs() {
	export ENCFS6_CONFIG="$1"
	echo "$2" | $ENCFS -S "$3" "$4"
	[ $? -eq 0 ] || echo "Mount $3 on $4 failed err: $?"
  if [ $QUIET -ne 1 ]; then
	  echo "encfs return: $? - $3 on $4"
  fi
}

PASS1=`cat $BASEDIR/pass1.txt`
PASS2=`cat $BASEDIR/pass2.txt`
PASS3=`cat $BASEDIR/pass3.txt`
PASS4=`cat $BASEDIR/pass4.txt`

if [ $ENC_DEC -eq 1 ]; then
	mount_encfs "$BASEDIR/level1.xml" "$PASS1" $SOURCE $TARGET1
	mount_encfs "$BASEDIR/level2.xml" "$PASS2" $TARGET1 $TARGET2
	mount_encfs "$BASEDIR/level3.xml" "$PASS3" $TARGET2 $TARGET3
	mount_encfs "$BASEDIR/level4.xml" "$PASS4" $TARGET3 $TARGET4
else
	mount_decfs "$BASEDIR/level4.xml" "$PASS4" $SOURCE $TARGET1
	mount_decfs "$BASEDIR/level3.xml" "$PASS3" $TARGET1 $TARGET2
	mount_decfs "$BASEDIR/level2.xml" "$PASS2" $TARGET2 $TARGET3
	mount_decfs "$BASEDIR/level1.xml" "$PASS1" $TARGET3 $TARGET4
fi

UNMOUNT_SCRIPT="$(mktemp --suffix .encfs)"
echo "#!/bin/bash/
fusermount -u $TARGET1
[ \$? -eq 0 ] || fusermount -u $TARGET1
[ \$? -eq 0 ] || fusermount -u $TARGET1
fusermount -u $TARGET2
[ \$? -eq 0 ] || fusermount -u $TARGET2
[ \$? -eq 0 ] || fusermount -u $TARGET2
fusermount -u $TARGET3
[ \$? -eq 0 ] || fusermount -u $TARGET3
[ \$? -eq 0 ] || fusermount -u $TARGET3
fusermount -u $TARGET4
[ \$? -eq 0 ] || fusermount -u $TARGET4
[ \$? -eq 0 ] || fusermount -u $TARGET4
" > $UNMOUNT_SCRIPT
chmod u+x $UNMOUNT_SCRIPT

if [ $QUIET -eq 1 ]; then
  echo $UNMOUNT_SCRIPT
else
  echo
  echo "Use this script file to unmount when finish the job: $UNMOUNT_SCRIPT"
fi

