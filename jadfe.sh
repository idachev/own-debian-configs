#!/bin/sh

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#Unmark what you want to change
SYSTEM_PROPERTIES=
SYSTEM_PROPERTIES=-Djadfe.jadexe=${BASEDIR}/jad $SYSTEM_PROPERTIES
# SYSTEM_PROPERTIES="-Djadfe.folder.launcher="<launch application that will be used for openning of folders>" $SYSTEM_PROPERTIES"
SYSTEM_PROPERTIES="-Djadfe.file.launcher=kate $SYSTEM_PROPERTIES"
#SYSTEM_PROPERTIES="-Djadfe.params="-r -s java -lnc -nocast -safe -o -b -lradix16 -space -dead -ff -noctor -nonlb -t2" $SYSTEM_PROPERTIES"
# SYSTEM_PROPERTIES="-Djadfe.temp="<the folder that will be used as temp folder>" $SYSTEM_PROPERTIES"
SYSTEM_PROPERTIES="-Djadfe.debug=true $SYSTEM_PROPERTIES"
# SYSTEM_PROPERTIES="-Djadfe.output.limit="<limit for output folder in bytes, -1 disables limit (it is default)>" $SYSTEM_PROPERTIES"
# SYSTEM_PROPERTIES="-Djadfe.tempout.limit="<limit for unpacking folder in bytes, -1 disables limit (it is default)>" $SYSTEM_PROPERTIES"

echo $SYSTEM_PROPERTIES
# -jces
java $SYSTEM_PROPERTIES -Djadfe.params="-s java -lnc -nocast -safe -o -b -lradix16 -space -dead -ff -noctor -nonlb -t2" -Ddebug=true -classpath "$BASEDIR/jadfe.jar:$CLASSPATH" com.jadfe.JadFrontEnd -r -l "$*"
