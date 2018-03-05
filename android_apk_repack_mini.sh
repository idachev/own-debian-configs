#!/bin/bash

cd $1

rm -fv ./META-INF/*

zip -r ../$1_mini.apk *

cd ..

~/bin/android_apk_sign.sh ./$1_mini.apk

