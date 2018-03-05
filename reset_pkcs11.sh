#!/bin/zsh
#set -v

# ubuntu old 2012
#MODULE=/usr/lib/onepin-opensc-pkcs11.so

# debian wheezy 7
#MODULE=/usr/lib/x86_64-linux-gnu/onepin-opensc-pkcs11.so

# ubuntu new 2015 and mint
#MODULE=/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
MODULE=/usr/lib/pcsc/drivers/ifd-acsccid.bundle/Contents/Linux/libacsccid.so

pkcs11-tool -I --module $MODULE

sudo service pcscd restart

sleep 5

pkcs11-tool -I --module $MODULE

echo
echo 'Add new module at "Security Devices" in Firefox'
echo "( the module on ubuntu $MODULE )"
echo
echo 'Execute this once for chrome:'
echo 'sudo apt-get install libnss3-tools'
echo 'modutil -dbdir sql:/home/'"$USER"'/.pki/nssdb/ -add "Card Reader PKCS#11 Module" -libfile '"$MODULE"

