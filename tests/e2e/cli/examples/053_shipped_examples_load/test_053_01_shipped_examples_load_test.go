package e2e

import (
	"os"
	"path/filepath"
	"testing"
)

// T053_01: every shipped new-format example loads clean through the binary. This
// is the reconciliation proof at the CLI level — pointing the real command at a
// real example's `.sloprail` exits 0, confirming the example grammar matches the
// spec-faithful scopes the loader enforces.
func TestT053_01_ShippedExamplesLoadCleanThroughTheBinary(t *testing.T) {
	e := New(t)
	repo := repoRootForExamples(t)

	// A representative spread across natures and both aliases: a gate with a
	// PreFileWrite alias (required-context-precondition), a context with a
	// PostFileWrite alias (eval-loop-maxing), a PostTagWrite context
	// (research-rigor), a structure gate (completeness-artifact-on-trigger), and a
	// gate+context+file-guard composite where a Stop gate reads a context's payload
	// (deterministic-refactoring-mode).
	for _, example := range []string{
		"required-context-precondition",
		"eval-loop-maxing",
		"research-rigor",
		"completeness-artifact-on-trigger",
		"interlinking",
		"marker-anchored-structure",
		"deterministic-refactoring-mode",
	} {
		example := example
		t.Run(example, func(t *testing.T) {
			dir := filepath.Join(repo, "examples", example)
			res := e.CLIDirect(dir, "sr-file", "declarations", dir)
			if res.Code != 0 {
				t.Fatalf("example %q must load clean through the binary, got exit %d:\n%s", example, res.Code, res.Output)
			}
		})
	}
}

// repoRootForExamples finds the module root so the shipped examples are reachable
// from the test's working directory.
func repoRootForExamples(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatal("could not find repo root (no go.mod up the tree)")
		}
		dir = parent
	}
}
