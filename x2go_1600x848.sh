#!/bin/bash

# cvt 1600 848
xrandr --newmode "1600x848" 111.50  1600 1696 1856 2112  848 851 861 881 -hsync +vsync

xrandr --addmode 'default' 1600x848

xrandr -s 1600x848

