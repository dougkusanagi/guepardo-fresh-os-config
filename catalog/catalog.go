// Package catalog embeds the shared application and profile metadata.
package catalog

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"path"
	"strings"
)

//go:embed apps.json
var data []byte

type Profile struct {
	ID          string   `json:"id"`
	Label       string   `json:"label"`
	LinuxRecipe string   `json:"linuxRecipe"`
	Platforms   []string `json:"platforms"`
}
type App struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Profiles  []string `json:"profiles"`
	DependsOn []string `json:"dependsOn"`
}
type Catalog struct {
	SchemaVersion int       `json:"schemaVersion"`
	Profiles      []Profile `json:"profiles"`
	Apps          []App     `json:"apps"`
}

func Load() (Catalog, error) { return Parse(data) }
func Parse(input []byte) (Catalog, error) {
	var c Catalog
	if err := json.Unmarshal(input, &c); err != nil {
		return c, err
	}
	if c.SchemaVersion != 1 {
		return c, fmt.Errorf("unsupported catalog version %d", c.SchemaVersion)
	}
	profiles := map[string]bool{}
	for _, p := range c.Profiles {
		if p.ID == "" || profiles[p.ID] {
			return c, fmt.Errorf("invalid/duplicate profile %q", p.ID)
		}
		profiles[p.ID] = true
		if p.LinuxRecipe != "" && (path.IsAbs(p.LinuxRecipe) || strings.Contains(p.LinuxRecipe, "..") || strings.Contains(p.LinuxRecipe, "\\")) {
			return c, fmt.Errorf("unsafe recipe %q", p.LinuxRecipe)
		}
	}
	apps := map[string]App{}
	for _, a := range c.Apps {
		if a.ID == "" || a.Name == "" {
			return c, fmt.Errorf("app ID/name is empty")
		}
		if _, ok := apps[a.ID]; ok {
			return c, fmt.Errorf("duplicate app %q", a.ID)
		}
		for _, profile := range a.Profiles {
			if !profiles[profile] {
				return c, fmt.Errorf("unknown profile %q", profile)
			}
		}
		apps[a.ID] = a
	}
	visited, visiting := map[string]bool{}, map[string]bool{}
	var visit func(string) error
	visit = func(id string) error {
		if visiting[id] {
			return fmt.Errorf("dependency cycle at %q", id)
		}
		if visited[id] {
			return nil
		}
		app, ok := apps[id]
		if !ok {
			return fmt.Errorf("unknown dependency %q", id)
		}
		visiting[id] = true
		for _, dep := range app.DependsOn {
			if err := visit(dep); err != nil {
				return err
			}
		}
		delete(visiting, id)
		visited[id] = true
		return nil
	}
	for id := range apps {
		if err := visit(id); err != nil {
			return c, err
		}
	}
	return c, nil
}
