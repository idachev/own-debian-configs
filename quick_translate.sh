#!/bin/bash

TMPNAME=$(mktemp -t 'tmp.XXXXXXXXXX.html')
TRANSLATION=$(xsel | translate-bin -f en -t bg)
echo $TRANSLATION > $TMPNAME
firefox $TMPNAME

