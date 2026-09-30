#!/usr/bin/env bash

section "Static network"
dnf_install NetworkManager
configure_static_ipv4_network
