package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNetworkPresetWithoutPrompts(t *testing.T) {
	wifi := activeNetwork{UUID: "wifi-uuid", Device: "wlan0", Kind: "Wi-Fi", Address: "192.168.1.10/24", DNS: "9.9.9.9"}
	cable := activeNetwork{UUID: "cable-uuid", Device: "eth0", Kind: "cabo"}
	for _, tc := range []struct {
		name         string
		networks     []activeNetwork
		device, uuid string
	}{
		{"wifi", []activeNetwork{wifi}, "wlan0", "wifi-uuid"},
		{"prefer cable", []activeNetwork{wifi, cable}, "eth0", "cable-uuid"},
		{"no network", nil, "", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			opts := options{}
			configureNetworkSettings(&opts, tc.networks)
			if opts.networkAddress != "192.168.1.77/24" || opts.networkGateway != "192.168.1.1" || opts.networkDNS != "1.1.1.1" || opts.networkInterface != tc.device || opts.networkUUID != tc.uuid {
				t.Fatalf("unexpected preset: %+v", opts)
			}
		})
	}
	opts := options{networkInterface: "wlan0"}
	configureNetworkSettings(&opts, []activeNetwork{wifi, cable})
	if opts.networkUUID != "wifi-uuid" {
		t.Fatal(opts)
	}
}

func TestDetectActiveNetworks(t *testing.T) {
	dir := t.TempDir()
	stub := `#!/bin/sh
case "$*" in
 '-t -f UUID,TYPE,DEVICE connection show --active')
 printf 'wifi-uuid:802-11-wireless:wlan0\ncable-uuid:802-3-ethernet:eth0\nvpn-uuid:vpn:tun0\nbridge-uuid:bridge:podman0\noff-uuid:ethernet:eth1\n' ;;
 '-g GENERAL.STATE device show eth1') echo '30 (disconnected)' ;;
 '-g GENERAL.STATE device show '*) echo '100 (connected)' ;;
 '-e no -g connection.id connection show uuid wifi-uuid') echo 'Casa: principal' ;;
 '-e no -g connection.id connection show uuid cable-uuid') echo 'Escritório' ;;
 '-g IP4.ADDRESS device show '*) printf '192.168.1.10/24\n192.168.1.11/24\n' ;;
 '-g IP4.GATEWAY device show '*) echo '192.168.1.1' ;;
 '-g IP4.DNS device show '*) printf '9.9.9.9\n1.1.1.1\n' ;;
 *) exit 42 ;;
esac
`
	if err := os.WriteFile(filepath.Join(dir, "nmcli"), []byte(stub), 0755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	nets, err := detectActiveNetworks()
	if err != nil {
		t.Fatal(err)
	}
	if len(nets) != 2 || nets[0].Name != "Casa: principal" || nets[0].Kind != "Wi-Fi" || nets[1].Kind != "cabo" || nets[0].Address != "192.168.1.10/24" || nets[0].DNS != "9.9.9.9" {
		t.Fatalf("wrong active networks: %+v", nets)
	}
	t.Setenv("PATH", t.TempDir())
	if _, err := detectActiveNetworks(); err == nil {
		t.Fatal("missing NetworkManager was ignored")
	}
}
