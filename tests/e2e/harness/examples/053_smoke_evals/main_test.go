package e2e

import (
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/sloprail/sloprail/tests/e2e/harness"
)

// The smoke evals (examples/_smoke/eval/<case>) are run against REAL agents by
// scripts/run-smoke-evals.sh. These tests prove the fixtures and their scorers
// without one: each case's seed and overlay are installed in a project with the
// plugin enabled, the mock plays the agent's expected path (and, for the negative
// runs, a path that skips the point of the case), and the case's own score.sh
// reads the mock's record the way it reads a real one. A scorer that passes a run
// that never hit the rule, or fails the run that recovered, is caught here.
var (
	newEnv = harness.New
	Turns  = harness.Turns
	Bash   = harness.Bash
	Write  = harness.Write
	Skill  = harness.Skill
)

func TestMain(m *testing.M) {
	code := m.Run()
	harness.Cleanup()
	os.Exit(code)
}

func repoRoot(t *testing.T) string {
	t.Helper()
	out, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		t.Fatalf("locate repo root: %v", err)
	}
	return strings.TrimSpace(string(out))
}

func fixtureDir(t *testing.T, name string) string {
	t.Helper()
	return filepath.Join(repoRoot(t), "examples", "_smoke", "eval", name)
}

// prompt is the fixture's prompt.md, the exact words the agent would receive.
func prompt(t *testing.T, name string) string {
	t.Helper()
	body, err := os.ReadFile(filepath.Join(fixtureDir(t, name), "prompt.md"))
	if err != nil {
		t.Fatal(err)
	}
	return strings.TrimSpace(string(body))
}

// copyTree copies src's contents into dst, keeping each file's mode (a rule's
// check script must stay executable).
func copyTree(t *testing.T, src, dst string) {
	t.Helper()
	err := filepath.WalkDir(src, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(src, p)
		target := filepath.Join(dst, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		body, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		return os.WriteFile(target, body, info.Mode().Perm())
	})
	if err != nil {
		t.Fatalf("copy %s: %v", src, err)
	}
}

// project is what sr-eval builds for the case: the seed committed first, the
// overlay's rules in a second commit, the plugin enabled.
func project(t *testing.T, e *harness.Env, name string) string {
	t.Helper()
	dir := fixtureDir(t, name)
	proj := e.Project()
	e.GitInitUnborn(proj)
	copyTree(t, filepath.Join(dir, "seed"), proj)
	if _, err := os.Stat(filepath.Join(dir, "overlay")); err == nil {
		copyTree(t, filepath.Join(dir, "overlay"), proj)
	}
	e.CommitSeedThenRules(proj, "seed")
	return proj
}

// score runs the case's score.sh over the mock's record, the way sr-eval does,
// and returns its exit code and output.
func score(t *testing.T, e *harness.Env, name, proj, sessionID string) (int, string) {
	t.Helper()
	h := os.Getenv("SR_HARNESS")
	if h == "" {
		h = "claude"
	}
	cmd := exec.Command(filepath.Join(fixtureDir(t, name), "score.sh"))
	cmd.Dir = fixtureDir(t, name)
	cmd.Env = append(os.Environ(),
		"SR_EVAL_HARNESS="+h,
		"SLOPRAIL_HARNESS="+h,
		"SR_EVAL_TRANSCRIPT="+e.TranscriptPath(proj, sessionID),
		"SR_EVAL_PROJECT_DIR="+proj,
		"SR_EVAL_FIXTURE_DIR="+fixtureDir(t, name),
		"SR_EVAL_BIN_DIR="+e.BinDir(),
		"SR_EVAL_AGENT_HOME="+e.HomeDir(),
	)
	out, err := cmd.CombinedOutput()
	if err == nil {
		return 0, string(out)
	}
	if ee, ok := err.(*exec.ExitError); ok {
		return ee.ExitCode(), string(out)
	}
	t.Fatalf("run score.sh of %s: %v\n%s", name, err, out)
	return -1, ""
}

func wantPass(t *testing.T, e *harness.Env, name, proj, sid string) {
	t.Helper()
	if code, out := score(t, e, name, proj, sid); code != 0 {
		t.Fatalf("%s: the recovered run must pass its scorer, got exit %d:\n%s", name, code, out)
	}
}

func wantFail(t *testing.T, e *harness.Env, name, proj, sid, why string) {
	t.Helper()
	if code, out := score(t, e, name, proj, sid); code != 1 {
		t.Fatalf("%s: %s must fail its scorer (exit 1), got exit %d:\n%s", name, why, code, out)
	}
}
