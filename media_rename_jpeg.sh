#!/bin/sh

# first do all lower case
rename -vf 'y/A-Z/a-z/' *.JPG
rename -vf 'y/A-Z/a-z/' *.jpg

# replace spaces with _
rename -vf 'y/ /_/' *.jpg

# add date taken to the file modify
jhead -ft *.jpg

# rename with adding date taken
jhead -n%Y%m%d-%H%M%S-%f *.jpg
