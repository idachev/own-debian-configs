#!/bin/bash

echo -e "PCI rescan..."

sudo bash -c 'echo 1 > /sys/bus/pci/rescan'

