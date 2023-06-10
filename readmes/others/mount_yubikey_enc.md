# Auto Mount Yubikey and Luks/GoCryptFs

The passwords are encrypted and stored to:
```bash
/root/.gnupg/mount/mount_dev_nvme1n1.enc
/root/.gnupg/mount/mount_dev_nvme2n1.enc
/root/.gnupg/mount/mount_home_idachev_storage_a_crypt.enc
```

The `~/bin/luks_mount.sh` will prompt only once for Yubikey openpgp card pin, and it will be cached
for 15s.

To encrypt the password we use the `~/.gnupg`.

## Encrypting Passwords

To encrypt use:

```bash
sudo -i
echo "MyTOPSecretPassword" | \
  gpg -q --encrypt --armor -r key@email.com > \
  ~/.gnupg/mount/mount_dev_nvme1n1.enc
```

To test that it can be decrypted use:
```bash
cat ~/.gnupg/mount/mount_dev_nvme1n1.enc | \
  gpg --pinentry-mode loopback -q --decrypt
```

## Configure GPG

In order GPG to use `gpg --pinentry-mode loopback` write this:

```text
allow-loopback-pinentry
```

Store this to: `/root/.gnupg/gpg-agent.conf`

And restart the agent with: `gpg-connect-agent reloadagent /bye`

To test use:

```bash
echo "test" | gpg -q --encrypt --armor -r key@email.com | \
  cat | gpg --pinentry-mode loopback -q --decrypt
```

Check the USB port the Yubikey work on some only with sudo and on some without

