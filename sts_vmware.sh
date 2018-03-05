#!/bin/zsh

# work around for e#290395 / LP: #458703
# https://bugs.eclipse.org/bugs/show_bug.cgi?id=290395
# https://bugs.launchpad.net/bugs/458703
export GDK_NATIVE_WINDOWS=true

STS_HOME=$HOME/lib/springsource/sts-2.9.1.RELEASE

STS=$STS_HOME/STS

exec $STS "$@"
