#!/bin/bash
# Start PC/SC Smart Card Daemon services

sudo systemctl start pcscd.service pcscd.socket
