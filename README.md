# own-debian-configs
My own debian scripts and configs

It should be cloned into ~/bin
```
cd ~/

mkdir bin

cd bin

git clone https://github.com/idachev/own-debian-configs.git .
```

# Setup home dir
To install all the bash/zsh and other programs settings in a clean debian/ubuntu/mint call
```
cd settings/linux/home

source create_links

ln -s ~/.ssh/id_rsa ~/.local_ssh_key
```

On macOS:
```
cd settings/osx/home

source create_links

ln -s ~/.ssh/id_rsa ~/.local_ssh_key
```

# Setup macOS system (/etc)
Copies of machine-level configs (sshd drop-ins, etc.). Restore with `sudo cp`,
do not symlink into `/etc`.

See `settings/osx/system/README.md`.


To add specifics only to the local shell config use:
```
~/.localrc
```

# Setup root home dir
To do this for the root home:
```
sudo -i

cd /home/<username>/bin/settings/linux/root

source create_links
```

See `settings/linux/root/README.md` for additional root setup, e.g. the
ZeroTier DNS fix for new machines joined to a ZeroTier network with managed DNS.

# Install all goodies
To install all useful programs on debian/ubuntu/mint call
```
apt_install_all_goodies.sh
```

CLI-only (Ubuntu 24.04):
```
apt_install_no_gui_noble.sh
```

On macOS (Homebrew + SDKMAN + nvm + rustup, safe to re-run):
```
./brew_install_no_gui.sh
```
CLI + GUI casks (Postman, Calibre, Thunderbird, Telegram, Slack, KeePassXC, JetBrains Toolbox):
```
./brew_install_all_goodies.sh
```
Docker Desktop and macFUSE may ask for a sudo password. Java 21 / Maven / Gradle come from SDKMAN, Node LTS from nvm, Rust from rustup.

# Custom Settings

## Terminal Profiles

Check `settings/linux/home/_manual_/gnome-terminal`

# External Tools

> Some of the tools are extracted in ~/lib/bin

* https://github.com/so-fancy/diff-so-fancy
* https://github.com/junegunn/fzf
* https://github.com/rupa/z
* https://github.com/eza-community/eza
* https://github.com/sharkdp/fd?tab=readme-ov-file
* https://github.com/phiresky/ripgrep-all
* https://github.com/BurntSushi/ripgrep
* https://github.com/unixorn/fzf-zsh-plugin?tab=readme-ov-file
* https://github.com/5hubham5ingh/js-util - build for local machine
