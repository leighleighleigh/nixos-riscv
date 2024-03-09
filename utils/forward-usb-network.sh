#!/usr/bin/env nix-shell
#!nix-shell -p nftables -i bash
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
sudo nft -f ./usb-masquerade.nftables
