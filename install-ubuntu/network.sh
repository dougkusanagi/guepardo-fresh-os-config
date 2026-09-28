#!/usr/bin/env bash

section "Static network"
apt_install network-manager
configure_static_ipv4_network
