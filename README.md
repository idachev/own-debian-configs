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

# Install all goodies
To install all useful programs call
```
apt_install_all_goodies.sh
```

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

