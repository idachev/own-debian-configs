#!/bin/zsh

# work around for e#290395 / LP: #458703
# https://bugs.eclipse.org/bugs/show_bug.cgi?id=290395
# https://bugs.launchpad.net/bugs/458703
export GDK_NATIVE_WINDOWS=true

export MOZILLA_FIVE_HOME="/usr/lib/xulrunner-$(/usr/bin/xulrunner-1.9.2 --gre-version)"

ECLIPSE_HOME=$HOME/lib/eclipse_python

ECLIPSE=$ECLIPSE_HOME/eclipse

exec $ECLIPSE "$@"

