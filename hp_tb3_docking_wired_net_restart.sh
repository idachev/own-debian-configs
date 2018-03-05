#!/bin/bash

PCI_SCAN_DELAY=5

(~/bin/pci_rescan.sh)

echo -e "Sleep ${PCI_SCAN_DELAY}s process rescan..."
sleep ${PCI_SCAN_DELAY}

(~/bin/kernel_mod_reload.sh tg3)

