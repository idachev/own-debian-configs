#!/bin/bash
# Stop PC/SC Smart Card Daemon services

sudo systemctl stop pcscd.service pcscd.socket
