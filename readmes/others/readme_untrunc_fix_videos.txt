
Use untrunc ok_from_same_camera.mp4 broken.mp4

Then crop by time wiht:

ffmpeg -i VID_20161106_202418.mp4_fixed.mp4 -ss 00:00:00 -t 00:01:37 -vcodec copy -acodec copy VID_20161106_202418.mp4_fixed_s2.mp4

