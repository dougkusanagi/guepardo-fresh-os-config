package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"strings"
	"unicode/utf8"
)

var pickerNames = []string{"CLI e servidor", "Desenvolvimento", "Stack web", "Desktop", "Jogos", "Fontes", "Rede IPv4", "Todos"}

type profilePicker struct {
	selected       map[string]bool
	active         int
	message        string
	wsl            bool
	linuxSelection map[string]bool
	wslSelection   map[string]bool
	width          int
	height         int
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
	return &profilePicker{selected: make(map[string]bool), width: 80, height: 32}
}

func (p *profilePicker) availableProfiles() []string {
	if p.wsl {
		return profileOrder[:3]
	}
	return profileOrder
}

func (p *profilePicker) names() []string {
	if p.wsl {
		return append(append([]string{}, pickerNames[:3]...), "Todos")
	}
	return pickerNames
}

func (p *profilePicker) allSelected() bool {
	for _, name := range p.availableProfiles() {
		if !p.selected[name] {
			return false
		}
	}
	return true
}

func (p *profilePicker) toggle(index int) {
	if index < 0 || index > len(p.availableProfiles()) {
		return
	}
	if index == len(p.availableProfiles()) {
		selectAll := !p.allSelected()
		for _, name := range p.availableProfiles() {
			p.selected[name] = selectAll
		}
	} else {
		name := p.availableProfiles()[index]
		p.selected[name] = !p.selected[name]
	}
	p.message = ""
}

func (p *profilePicker) profiles() string {
	var selected []string
	for _, name := range p.availableProfiles() {
		if p.selected[name] {
			selected = append(selected, name)
		}
	}
	return strings.Join(selected, ",")
}

// Switching environments applies a recommendation, while preserving the Linux selection.
func (p *profilePicker) switchEnvironment() {
	if !p.wsl {
		p.linuxSelection = p.selected
		if p.wslSelection == nil {
			p.wslSelection = map[string]bool{"cli": true, "dev": true, "web": true}
		}
		p.selected = p.wslSelection
	} else {
		p.wslSelection = p.selected
		p.selected = p.linuxSelection
	}
	p.wsl = !p.wsl
	p.active = 0
	p.message = ""
}

func fitPickerText(value string, width int) string {
	if width < 1 {
		return ""
	}
	if utf8.RuneCountInString(value) <= width {
		return value
	}
	return string([]rune(value)[:width-1]) + "…"
}

func (p *profilePicker) render(w io.Writer, colored bool) {
	width := p.width - 6
	if width > 72 {
		width = 72
	}
	if width < 20 {
		width = 20
	}
	paint := func(code, value string) string { return color(code, value, colored) }
	line := func(value string) { fmt.Fprintln(w, "   "+fitPickerText(value, width)) }
	fmt.Fprint(w, "\x1b[H\x1b[2J")
	fmt.Fprintln(w)
	subtitle := "  /  prepare seu próximo ambiente"
	if width < 44 {
		subtitle = "  /  seu ambiente"
	}
	fmt.Fprintln(w, "   "+paint("1;38;2;167;139;250", "guepardo")+paint("38;2;148;163;184", subtitle))
	fmt.Fprintln(w)
	linux, wsl := "  Linux  ", "  WSL  "
	if p.wsl {
		wsl = paint("1;38;2;17;24;39;48;2;167;139;250", wsl)
		linux = paint("38;2;148;163;184", linux)
	} else {
		linux = paint("1;38;2;17;24;39;48;2;167;139;250", linux)
		wsl = paint("38;2;148;163;184", wsl)
	}
	modeHint := "    Tab / W trocar"
	if width < 40 {
		modeHint = "    Tab/W"
	}
	fmt.Fprintln(w, "   "+linux+"  "+wsl+paint("38;2;148;163;184", modeHint))
	if p.wsl {
		line("Ferramentas para o Ubuntu dentro do Windows.")
	} else {
		line("Escolha o que quer ter pronto neste computador.")
	}
	fmt.Fprintln(w)
	spacious := p.height >= 32
	for i, name := range p.names() {
		checked := i == len(p.availableProfiles()) && p.allSelected()
		if i < len(p.availableProfiles()) {
			checked = p.selected[p.availableProfiles()[i]]
		}
		mark := "○"
		if checked {
			mark = "●"
		}
		cursor := " "
		if i == p.active {
			cursor = "▸"
		}
		value := fmt.Sprintf(" %s  %d  %s  %s", cursor, i+1, mark, name)
		value = fitPickerText(value, width)
		code := "38;2;203;213;225"
		if checked {
			code = "38;2;110;231;183"
		}
		if i == p.active {
			code = "1;38;2;237;233;254;48;2;49;41;70"
			value += strings.Repeat(" ", max(0, width-utf8.RuneCountInString(value)))
		}
		fmt.Fprintln(w, "   "+paint(code, value))
		if spacious {
			fmt.Fprintln(w)
		}
	}
	description := "Seleciona todos os módulos, inclusive a rede IPv4."
	if p.wsl {
		description = "Seleciona CLI, desenvolvimento e stack web."
	}
	if p.active < len(p.availableProfiles()) {
		description = profileLabels[p.availableProfiles()[p.active]]
	}
	fmt.Fprintln(w, "   "+paint("38;2;148;163;184", fitPickerText(description, width)))
	fmt.Fprintln(w)
	count := 0
	for _, name := range p.availableProfiles() {
		if p.selected[name] {
			count++
		}
	}
	summary := fmt.Sprintf("%d módulos selecionados", count)
	hints := fmt.Sprintf("↑↓ navegar · Espaço / 1–%d selecionar · Q sair", len(p.names()))
	if width < 48 {
		summary = fmt.Sprintf("%d módulos", count)
		hints = "↑↓ mover · Espaço marcar · Q sair"
	}
	fmt.Fprintln(w, "   "+paint("1;38;2;167;139;250", summary)+"   "+paint("38;2;148;163;184", "Enter continuar"))
	line(hints)
	if p.selected["network"] {
		fmt.Fprintln(w, "   "+paint("38;2;251;191;36", fitPickerText("Rede selecionada: a conexão será alterada.", width)))
	}
	if p.message != "" {
		fmt.Fprintln(w, "   "+paint("38;2;251;191;36", fitPickerText(p.message, width)))
	}
}

// selectProfiles reads one key at a time from a terminal already in raw mode.
func selectProfiles(input io.Reader, output io.Writer, colored bool) (string, error) {
	return selectProfilesWithPicker(input, output, colored, newProfilePicker())
}

func selectProfilesWithPicker(input io.Reader, output io.Writer, colored bool, p *profilePicker) (string, error) {
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
		case key == '\t' || key == 'w' || key == 'W':
			p.switchEnvironment()
		case key == ' ':
			p.toggle(p.active)
		case key >= '1' && key < '1'+byte(len(p.names())):
			p.active = int(key - '1')
			p.toggle(p.active)
		case key == 'a' || key == 'A':
			p.active = len(p.availableProfiles())
			p.toggle(p.active)
		case key == 'j' || key == 'J':
			p.active = (p.active + 1) % len(p.names())
		case key == 'k' || key == 'K':
			p.active = (p.active + len(p.names()) - 1) % len(p.names())
		case key == 'q' || key == 'Q' || key == 3:
			return "", errors.New("seleção cancelada")
		case key == 27:
			// Arrow keys arrive as ESC [ A/B.
			if next, err := reader.ReadByte(); err == nil && next == '[' {
				if direction, err := reader.ReadByte(); err == nil {
					switch direction {
					case 'A':
						p.active = (p.active + len(p.names()) - 1) % len(p.names())
					case 'C', 'D':
						p.switchEnvironment()
					case 'B':
						p.active = (p.active + 1) % len(p.names())
					}
				}
			}
		}
	}
}
