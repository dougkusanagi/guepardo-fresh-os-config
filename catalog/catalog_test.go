package catalog

import (
	"encoding/json"
	"testing"
)

func TestCatalogDependencies(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if len(c.Apps) < 60 {
		t.Fatalf("catalog lost apps: %d", len(c.Apps))
	}
	for _, test := range []struct {
		name   string
		mutate func(*Catalog)
	}{
		{"duplicate", func(c *Catalog) { c.Apps = append(c.Apps, c.Apps[0]) }},
		{"missing dependency", func(c *Catalog) { c.Apps[0].DependsOn = []string{"missing"} }},
		{"cycle", func(c *Catalog) { c.Apps[0].DependsOn = []string{c.Apps[0].ID} }},
		{"unsafe recipe", func(c *Catalog) { c.Profiles[0].LinuxRecipe = "../secrets" }},
	} {
		t.Run(test.name, func(t *testing.T) {
			fresh, _ := Load()
			test.mutate(&fresh)
			raw, _ := json.Marshal(fresh)
			if _, err := Parse(raw); err == nil {
				t.Fatal("invalid catalog accepted")
			}
		})
	}
}
