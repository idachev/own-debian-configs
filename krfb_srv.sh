#!/usr/bin/python

# Load extra functionality from the 'socket' and 'os' modules
from socket import socket, AF_INET, SOCK_STREAM
from os import execl

# Listen for a connection
server = socket(AF_INET, SOCK_STREAM) # This is an Internet (TCP) connection
server.bind(('127.0.0.1', 5900))      # Listen for a local connection on port 5,900
server.listen(1)                      # Listen for exactly 1 connection
sock = server.accept()[0]             # Accept the connection

# Attach krfb to this connection
execl('/usr/bin/krfb', 'krfb', '--kinetd', str(sock.fileno()))

