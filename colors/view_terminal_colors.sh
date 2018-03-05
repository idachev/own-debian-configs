#!/bin/bash
echo -e "\e[0mCOLOR_NC (No color)"
echo -e "\e[1;37mCOLOR_WHITE\t\e[0;30mCOLOR_BLACK"
echo -e "\e[0;34mCOLOR_BLUE\t\e[1;34mCOLOR_LIGHT_BLUE"
echo -e "\e[0;32mCOLOR_GREEN\t\e[1;32mCOLOR_LIGHT_GREEN"
echo -e "\e[0;36mCOLOR_CYAN\t\e[1;36mCOLOR_LIGHT_CYAN"
echo -e "\e[0;31mCOLOR_RED\t\e[1;31mCOLOR_LIGHT_RED"
echo -e "\e[0;35mCOLOR_PURPLE\t\e[1;35mCOLOR_LIGHT_PURPLE"
echo -e "\e[0;33mCOLOR_YELLOW\t\e[1;33mCOLOR_LIGHT_YELLOW"
echo -e "\e[1;30mCOLOR_GRAY\t\e[0;37mCOLOR_LIGHT_GRAY"

echo
echo "Set the following to gnome terminal profile:"
echo -e "\tColors\tBright Colors"
#echo -e "Black\t#4E4E4E\t#7C7C7C"
echo -e "Black\t#7E7E7E\t#9C9C9C"
echo -e "Red\t#FF6C60\t#FFB6B0"
echo -e "Green\t#A8FF60\t#CEFFAB"
echo -e "Yellow\t#FFFFB6\t#FFFFCB"
echo -e "Blue\t#96CBFE\t#B5DCFE"
echo -e "Magenta\t#FF73FD\t#FF9CFE"
echo -e "Cyan\t#C6C5FE\t#DFDFFE"
echo -e "White\t#EEEEEE\t#FFFFFF"

echo
echo -e "For gnome-terminal use this:"
echo "gconftool-2 -t str --set /apps/gnome-terminal/profiles/Default/palette \"#7E7E7E7E7E7E:#FFFF6C6C6060:#A8A8FFFF6060:#FFFFFFFFB6B6:#9696CBCBFEFE:#FFFF7373FDFD:#C6C6C5C5FEFE:#EEEEEEEEEEEE:#9C9C9C9C9C9C:#FFFFB6B6B0B0:#CECEFFFFABAB:#FFFFFFFFCBCB:#B5B5DCDCFEFE:#FFFF9C9CFEFE:#DFDFDFDFFEFE:#FFFFFFFFFFFF\""
echo
echo -e "Also use the same palette = \"#7E7...\" above in terminator config: ~/.config/terminator/config"

echo
echo -e "For konsole use this(need to choose it from settings):"
echo "cp ~/bin/colors/konsole.colorscheme ~/.kde/share/apps/konsole"

