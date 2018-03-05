#!/bin/bash

ORIGINAL_APK=$1
SIGNED_APK=$(echo "$ORIGINAL_APK" | sed 's/\.apk/-signed\.apk/')
ALIGNED_APK=$(echo "$ORIGINAL_APK" | sed 's/\.apk/-aligned\.apk/')

KEYSTORE=~/.android/debug.keystore
ZIPALIGN=~/lib/android-sdk/android-sdk-linux/tools/zipalign

jarsigner -verbose -keystore $KEYSTORE -storepass android -signedjar $SIGNED_APK $ORIGINAL_APK androiddebugkey

$ZIPALIGN -f 4 $SIGNED_APK $ALIGNED_APK

