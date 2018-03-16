#!/bin/zsh
#set -v

MODULE=/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so

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

