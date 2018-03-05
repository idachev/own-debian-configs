#!/bin/bash

rename -vf 's/-//g' *;
rename -vf 's/\.([0-9])/$1/g' *
rename -vf 's/([0-9])3gp/$1.3gp/g' *
rename -vf 's/ /_/g' *
rename -vf 's/^([0-9].*).jpg/IMG_$1.jpg/g' *
rename -vf 's/^([0-9].*).3gp/VID_$1.3gp/g' *
rename -vf 's/^([0-9].*).mp4/VID_$1.mp4/g' *

