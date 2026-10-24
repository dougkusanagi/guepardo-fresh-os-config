package main

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNetworkSelection(t *testing.T) {
	wifi := activeNetwork{UUID: "wifi-uuid", Device: "wlan0", Name: "Minha rede: casa", Kind: "Wi-Fi", Address: "192.168.1.10/24", Gateway: "192.168.1.1", DNS: "192.168.1.1"}
	cable := activeNetwork{UUID: "cable-uuid", Device: "eth0", Name: "Rede do escritório", Kind: "cabo", Address: "10.0.0.5/24", Gateway: "10.0.0.1"}
	for _, tc := range []struct {
		name                         string
		nets                         []activeNetwork
		input, device, address, uuid string
	}{
		{"single uses current defaults", []activeNetwork{wifi}, "\n\n\n", "wlan0", "192.168.1.10/24", "wifi-uuid"},
		{"multiple retries invalid choices", []activeNetwork{wifi, cable}, "0\nfoo\n3\n2\n\n\n\n", "eth0", "10.0.0.5/24", "cable-uuid"},
		{"change suggested IP", []activeNetwork{wifi}, "192.168.1.77/24\n\n\n", "wlan0", "192.168.1.77/24", "wifi-uuid"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			opts := options{}
			var out bytes.Buffer
			if err := promptNetworkSettingsWithNetworks(&opts, strings.NewReader(tc.input), &out, tc.nets); err != nil {
				t.Fatal(err)
			}
			if opts.networkInterface != tc.device || opts.networkAddress != tc.address || opts.networkUUID != tc.uuid {
				t.Fatalf("wrong selection: %+v", opts)
			}
			if strings.Contains(out.String(), "Interface de rede") {
				t.Fatal("detected network still asks for interface name")
			}
			if len(tc.nets) > 1 && (!strings.Contains(out.String(), "1) Minha rede: casa (Wi-Fi)") || !strings.Contains(out.String(), "2) Rede do escritório (cabo)")) {
				t.Fatal(out.String())
			}
		})
	}
	opts := options{}
	if err := promptNetworkSettingsWithNetworks(&opts, strings.NewReader("q\n"), io.Discard, []activeNetwork{wifi, cable}); err == nil {
		t.Fatal("cancellation ignored")
	}
	opts = options{networkInterface: "wlan0", networkAddress: "192.168.1.99/24", networkGateway: "192.168.1.1", networkDNS: "9.9.9.9"}
	if err := promptNetworkSettingsWithNetworks(&opts, strings.NewReader(""), io.Discard, []activeNetwork{wifi, cable}); err != nil {
		t.Fatal(err)
	}
	if opts.networkAddress != "192.168.1.99/24" || opts.networkDNS != "9.9.9.9" || opts.networkUUID != "wifi-uuid" {
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
