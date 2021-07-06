#!/bin/bash

[[ "${1}" -ne "ppp0" ]] && exit

if [[ "${2}" -eq "up" ]]
then
  ip route add 172.16.0.0/24 dev ppp0
fi
