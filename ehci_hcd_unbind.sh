#!/bin/sh

cd /sys/bus/pci/drivers/ehci_hcd
echo "Listing all 0000:00:... files:"
find ./ -name '0000:00:*' -print

echo
echo "Do the following for above files"
echo "cd /sys/bus/pci/drivers/ehci_hcd"
echo "sudo sh -c 'echo -n \"0000:00:xx.x\" > unbind'"

