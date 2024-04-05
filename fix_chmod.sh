#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set -x

chmod -R go-wrx *

EXTS='*.jpg *.thm *.mov *.avi *.png *.wmv *.pef *.3gp *.mp4 *.flv *.vob *.bup *.pdf *.txt *.psd'
 
for i in $EXTS; do
  find -type f -iname "$i" -print0 | xargs -0 chmod -x
done

