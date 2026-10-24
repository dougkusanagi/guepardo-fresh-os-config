package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"strconv"
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
		// Current values are suggestions only; the user confirms or replaces each one.
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

func promptDetectedNetwork(opts *options, reader *bufio.Reader, output io.Writer, networks []activeNetwork) (*activeNetwork, error) {
	if opts.networkInterface != "" {
		for i := range networks {
			if networks[i].Device == opts.networkInterface {
				return &networks[i], nil
			}
		}
		return nil, nil
	}
	if len(networks) == 0 {
		return nil, nil
	}
	selected := 0
	if len(networks) > 1 {
		fmt.Fprintln(output, "  Escolha a rede que receberá o IP fixo:")
		for i, n := range networks {
			fmt.Fprintf(output, "    %d) %s (%s)\n", i+1, n.Name, n.Kind)
		}
		for {
			fmt.Fprintf(output, "  Rede [1–%d, Q cancela]: ", len(networks))
			line, err := reader.ReadString('\n')
			if err != nil {
				return nil, fmt.Errorf("não consegui ler a rede: %w", err)
			}
			value := strings.TrimSpace(line)
			if strings.EqualFold(value, "q") {
				return nil, errors.New("configuração de rede cancelada")
			}
			index, err := strconv.Atoi(value)
			if err == nil && index >= 1 && index <= len(networks) {
				selected = index - 1
				break
			}
			fmt.Fprintln(output, "  Digite o número de uma das redes acima.")
		}
	}
	n := &networks[selected]
	opts.networkInterface = n.Device
	fmt.Fprintf(output, "  Rede selecionada: %s (%s)\n", n.Name, n.Kind)
	return n, nil
}
