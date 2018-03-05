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

cd /home/<username>/settings/linux/root

source create_links
```

# Install all goodies
To install all useful programs call
```
apt_install_all_goodies.sh
```
