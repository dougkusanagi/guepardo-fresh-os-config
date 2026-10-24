package main

import (
	"context"
	"os/exec"
	"strings"
	"time"
)

type activeNetwork struct {
	UUID, Device, Name, Kind, Address, Gateway, DNS string
}

func nmcliValues(args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nmcli", args...)
	data, err := cmd.Output()
	return strings.TrimSpace(string(data)), err
}

func detectActiveNetworks() ([]activeNetwork, error) {
	// Names are queried separately: colons/backslashes in SSIDs must not split fields.
	data, err := nmcliValues("-t", "-f", "UUID,TYPE,DEVICE", "connection", "show", "--active")
	if err != nil {
		return nil, err
	}
	var networks []activeNetwork
	for _, line := range strings.Split(data, "\n") {
		fields := strings.Split(line, ":")
		if len(fields) != 3 || fields[2] == "" || fields[2] == "lo" {
			continue
		}
		kind := ""
		switch fields[1] {
		case "802-11-wireless", "wifi":
			kind = "Wi-Fi"
		case "802-3-ethernet", "ethernet":
			kind = "cabo"
		default:
			continue // Never offer VPNs, loopback, containers or bridges.
		}
		state, err := nmcliValues("-g", "GENERAL.STATE", "device", "show", fields[2])
		if err != nil || !strings.HasPrefix(state, "100") {
			continue
		}
		name, err := nmcliValues("-e", "no", "-g", "connection.id", "connection", "show", "uuid", fields[0])
		if err != nil || name == "" {
			name = fields[2]
		}
		cleanName := strings.Map(func(r rune) rune {
			if r < 32 || r == 127 {
				return ' '
			}
			return r
		}, name)
		n := activeNetwork{UUID: fields[0], Device: fields[2], Name: cleanName, Kind: kind}
		// Keep discovery information available for diagnostics.
		n.Address, _ = nmcliValues("-g", "IP4.ADDRESS", "device", "show", n.Device)
		n.Gateway, _ = nmcliValues("-g", "IP4.GATEWAY", "device", "show", n.Device)
		n.DNS, _ = nmcliValues("-g", "IP4.DNS", "device", "show", n.Device)
		n.Address = strings.Split(n.Address, "\n")[0]
		n.Gateway = strings.Split(n.Gateway, "\n")[0]
		n.DNS = strings.Split(n.DNS, "\n")[0]
		networks = append(networks, n)
	}
	return networks, nil
}

// configureNetworkSettings uses the personal preset without reading stdin.
// Prefer an active wired connection when both Ethernet and Wi-Fi are available.
func configureNetworkSettings(opts *options, networks []activeNetwork) {
	if opts.networkAddress == "" {
		opts.networkAddress = "192.168.1.77/24"
	}
	if opts.networkGateway == "" {
		opts.networkGateway = "192.168.1.1"
	}
	if opts.networkDNS == "" {
		opts.networkDNS = "1.1.1.1"
	}
	selected := -1
	for i, network := range networks {
		if opts.networkInterface != "" {
			if network.Device == opts.networkInterface {
				selected = i
				break
			}
		} else if selected == -1 || network.Kind == "cabo" {
			selected = i
			if network.Kind == "cabo" {
				break
			}
		}
	}
	if selected >= 0 {
		opts.networkInterface = networks[selected].Device
		opts.networkUUID = networks[selected].UUID
	}
}
