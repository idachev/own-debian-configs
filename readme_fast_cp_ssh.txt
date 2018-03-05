tar -c -f - ~/src | mbuffer -s 1K -m 512M | ssh 10.0.0.10 "tar xf - -C ~/dst/"

Using compression can help only if you use multicore pigz and the connection is slow otherwise above is fastest.

