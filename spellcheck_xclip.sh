#!/bin/bash

TMP_CLIP="$(mktemp)"

# Copy clipboard contents to a temp file
xclip -selection XA_CLIPBOARD -o > $TMP_CLIP

# Run aspell on that file
aspell check $TMP_CLIP

# Copy the results back to the clipboard
cat $TMP_CLIP | xclip -selection XA_CLIPBOARD

echo "Done"

