package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"strings"
)

var pickerNames = []string{"CLI e servidor", "Desenvolvimento", "Stack web", "Desktop", "Jogos", "Fontes", "Rede IPv4", "Todos"}

type profilePicker struct {
	selected map[string]bool
	active   int
	message  string
}

// Raw terminal mode disables output processing, so line feeds need a carriage return.
type crlfWriter struct{ io.Writer }

func (w crlfWriter) Write(data []byte) (int, error) {
	converted := strings.ReplaceAll(string(data), "\n", "\r\n")
	_, err := io.WriteString(w.Writer, converted)
	if err != nil {
		return 0, err
	}
	return len(data), nil
}

func newProfilePicker() *profilePicker {
	return &profilePicker{selected: make(map[string]bool)}
}

func (p *profilePicker) allSelected() bool {
	for _, name := range profileOrder {
		if !p.selected[name] {
			return false
		}
	}
	return true
}

func (p *profilePicker) toggle(index int) {
	if index == len(profileOrder) {
		selectAll := !p.allSelected()
		for _, name := range profileOrder {
			p.selected[name] = selectAll
		}
	} else {
		name := profileOrder[index]
		p.selected[name] = !p.selected[name]
	}
	p.message = ""
}

func (p *profilePicker) profiles() string {
	var selected []string
	for _, name := range profileOrder {
		if p.selected[name] {
			selected = append(selected, name)
		}
	}
	return strings.Join(selected, ",")
}

func (p *profilePicker) render(w io.Writer, colored bool) {
	fmt.Fprint(w, "\x1b[H\x1b[2J")
	fmt.Fprintln(w, color("1;36", "  GUEPARDO  /  Escolha os perfis", colored))
	fmt.Fprintln(w, "  ↑↓ navegar  ·  Espaço ou 1–8 marcar  ·  Enter continuar")
	fmt.Fprintln(w)
	for i, name := range pickerNames {
		checked := i == len(profileOrder) && p.allSelected()
		if i < len(profileOrder) {
			checked = p.selected[profileOrder[i]]
		}
		mark, cursor := " ", " "
		if checked {
			mark = "x"
		}
		if i == p.active {
			cursor = "›"
		}
		line := fmt.Sprintf("  %s [%s] %d  %s", cursor, mark, i+1, name)
		if i == p.active {
			line = color("1;36", line, colored)
		}
		fmt.Fprintln(w, line)
	}
	fmt.Fprintln(w)
	count := 0
	for _, name := range profileOrder {
		if p.selected[name] {
			count++
		}
	}
	fmt.Fprintf(w, "  %d perfis selecionados · 8 marca todos · Q cancela\n", count)
	if p.selected["network"] {
		fmt.Fprintln(w, color("33", "  Rede altera a conexão; os dados IPv4 serão solicitados.", colored))
	} else {
		fmt.Fprintln(w, "  Rede altera a conexão; escolha apenas se precisar.")
	}
	if p.message != "" {
		fmt.Fprintln(w, color("1;33", "  "+p.message, colored))
	}
}

// selectProfiles reads one key at a time from a terminal already in raw mode.
func selectProfiles(input io.Reader, output io.Writer, colored bool) (string, error) {
	p := newProfilePicker()
	reader := bufio.NewReader(input)
	for {
		p.render(output, colored)
		key, err := reader.ReadByte()
		if err != nil {
			return "", err
		}
		switch {
		case key == '\r' || key == '\n':
			if selection := p.profiles(); selection != "" {
				return selection, nil
			}
			p.message = "Marque ao menos um perfil para continuar."
		case key == ' ':
			p.toggle(p.active)
		case key >= '1' && key <= '8':
			p.active = int(key - '1')
			p.toggle(p.active)
		case key == 'a' || key == 'A':
			p.active = len(profileOrder)
			p.toggle(p.active)
		case key == 'j' || key == 'J':
			p.active = (p.active + 1) % len(pickerNames)
		case key == 'k' || key == 'K':
			p.active = (p.active + len(pickerNames) - 1) % len(pickerNames)
		case key == 'q' || key == 'Q' || key == 3:
			return "", errors.New("seleção cancelada")
		case key == 27:
			// Arrow keys arrive as ESC [ A/B.
			if next, err := reader.ReadByte(); err == nil && next == '[' {
				if direction, err := reader.ReadByte(); err == nil {
					switch direction {
					case 'A':
						p.active = (p.active + len(pickerNames) - 1) % len(pickerNames)
					case 'B':
						p.active = (p.active + 1) % len(pickerNames)
					}
				}
			}
		}
	}
}
