#!/bin/bah

# Used parameters
# -m to mirror
# -k to make relative links
# -p parameter tells wget to include all files, including images.
# -e robots=off you don't want wget to obey by the robots.txt file
# -U mozilla as your browsers identity.

# --wait to wait econds between downloads used with random wait to produce random coefficient
# --random-wait to let wget chose a random number of seconds to wait, avoid get into black list.

# Other Useful wget Parameters:
# --limit-rate=20k limits the rate at which it downloads files.
# -b continues wget after logging out.
# -o $HOME/wget_log.txt logs the output
wget --wait 3 --random-wait -m -k -p -e robots=off -U mozilla --limit-rate=100k -b $1

