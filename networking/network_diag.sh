#!/bin/bash -xv

# Color Variables
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD=$(tput bold)
RESET='\033[0m'

# Gathering Network Data
network=$(cat "/proc/net/"* | grep -vE "^[0-9 ]+" | awk '{print $1,$2}')
IP6_addrs=$(ip -o addr show scope global | awk '{print $2,$3}'| grep '^[ef]\:' || true )

# Displaying Network Information
printf "$GREEN$RESET" "\t\e[32m${network}${BOLD}\n"

for ix in $IFACE; do
    printf "$GREEN$RESET" "\t\e[32m${ix}${BOLD}\n"
    ipv4=$(ip -o -4 addr show $ix | awk '{print $4}')
    ipv6=$(ip -o -6 addr show $ix | awk '{print $4}')
    metrics=$(cat /proc/net/dev | grep $ix | awk '{print $2,$3,$10,$11}')
    printf "$GREEN$RESET" "\t\e[32mIPv4 Addresses: ${ipv4}${BOLD}\n"
    printf "$GREEN$RESET" "\t\e[32mIPv6 Addresses: ${ipv6}${BOLD}\n"
    printf "$GREEN$RESET" "\t\e[32mMetrics: ${metrics}${BOLD}\n"
done

routes=$(netstat -nr | awk '{print $1,$2,$3,$8}')
printf "$GREEN$RESET" "\t\e[32mRoutes: ${routes}${BOLD}\n"

arp=$(cat /proc/net/"$ARPRES" | grep -v '^[0-9 ]+' | awk '{print $4,$5}')
printf "$GREEN$RESET" "\t\e[32mARP Cache: ${arp}${BOLD}\n"

connections=$(cat /proc/net/tcp | awk '{print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13}')
printf "$GREEN$RESET" "\t\e[32mActive Connections: ${connections}${BOLD}\n"

printf "$GREEN$RESET" "\t\e[32m------------------------------------------------${BOLD}\n"
