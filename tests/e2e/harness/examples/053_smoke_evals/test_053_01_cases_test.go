package e2e

import (
	"testing"

	"github.com/sloprail/sloprail/tests/e2e/harness"
)

// Each test plays one smoke case twice through the mock: the path a healthy agent
// takes (the scorer must pass it) and a path that skips what the case is about (the
// scorer must fail it). The scorer is the case's own score.sh.

// T053_01: session-context — the agent answers from the note it was given.
func TestT053_01_SessionContext(t *testing.T) {
	const c = "session-context"
	e := newEnv(t)
	proj := project(t, e, c)
	e.Run(proj, "s-053-01a", prompt(t, c), Turns("", harness.Say("a1", "The file is .sloprail/file-guard/structure.yaml")))
	wantPass(t, e, c, proj, "s-053-01a")

	proj = project(t, e, c)
	e.Run(proj, "s-053-01b", prompt(t, c), Turns("", harness.Say("a1", "I was not given a note about any file.")))
	wantFail(t, e, c, proj, "s-053-01b", "an answer that does not name the file")
}

// T053_02: prewrite-gate — the markdown write outside docs/ is refused, then lands in docs/.
func TestT053_02_PreWriteGate(t *testing.T) {
	const c = "prewrite-gate"
	e := newEnv(t)
	proj := project(t, e, c)
	e.Run(proj, "s-053-02a", prompt(t, c), Turns("done",
		Write("w1", "CHANGELOG.md", "v1 - first release\n"),
		Write("w2", "docs/CHANGELOG.md", "v1 - first release\n"),
	))
	wantPass(t, e, c, proj, "s-053-02a")

	proj = project(t, e, c)
	e.Run(proj, "s-053-02b", prompt(t, c), Turns("done",
		Write("w1", "CHANGELOG.md", "v1 - first release\n"),
	))
	wantFail(t, e, c, proj, "s-053-02b", "a refusal never recovered from")

	proj = project(t, e, c)
	e.Run(proj, "s-053-02c", prompt(t, c), Turns("done",
		Write("w1", "docs/CHANGELOG.md", "v1 - first release\n"),
	))
	wantFail(t, e, c, proj, "s-053-02c", "a run that never met the gate")
}

// T053_03: command-gate — rm is refused, git rm goes through.
func TestT053_03_CommandGate(t *testing.T) {
	const c = "command-gate"
	e := newEnv(t)
	proj := project(t, e, c)
	e.Run(proj, "s-053-03a", prompt(t, c), Turns("done",
		Bash("b1", "rm scratch.txt"),
		Bash("b2", "git rm scratch.txt"),
	))
	wantPass(t, e, c, proj, "s-053-03a")

	proj = project(t, e, c)
	e.Run(proj, "s-053-03b", prompt(t, c), Turns("done",
		Bash("b1", "rm scratch.txt"),
	))
	wantFail(t, e, c, proj, "s-053-03b", "a refusal never recovered from")

	proj = project(t, e, c)
	e.Run(proj, "s-053-03c", prompt(t, c), Turns("done",
		Bash("b1", "git rm scratch.txt"),
	))
	wantFail(t, e, c, proj, "s-053-03c", "a run that never met the gate")
}

// T053_04: stop-gate — the first Stop is refused; the agent writes SUMMARY.md; the next passes.
func TestT053_04_StopGate(t *testing.T) {
	const c = "stop-gate"
	e := newEnv(t)
	proj := project(t, e, c)
	e.Run(proj, "s-053-04a", prompt(t, c), Turns("fixed", Write("w1", "greeting.txt", "hello world\n")))
	e.Run(proj, "s-053-04a", "continue", Turns("summarized", Write("w2", "SUMMARY.md", "fixed the typo\n")))
	wantPass(t, e, c, proj, "s-053-04a")

	proj = project(t, e, c)
	e.Run(proj, "s-053-04b", prompt(t, c), Turns("fixed", Write("w1", "greeting.txt", "hello world\n")))
	wantFail(t, e, c, proj, "s-053-04b", "a turn that stayed refused with the work undone")
}

// T053_05: file-guard-stop — a committed record without an email is refused at Stop; the fix is committed.
func TestT053_05_FileGuardStop(t *testing.T) {
	const c = "file-guard-stop"
	bad := "[\n  {\"id\": 1, \"email\": \"ada@example.com\"},\n  {\"id\": 2, \"email\": \"grace@example.com\"},\n  {\"id\": 3}\n]\n"
	good := "[\n  {\"id\": 1, \"email\": \"ada@example.com\"},\n  {\"id\": 2, \"email\": \"grace@example.com\"},\n  {\"id\": 3, \"email\": \"user3@example.com\"}\n]\n"
	e := newEnv(t)
	proj := project(t, e, c)
	e.Run(proj, "s-053-05a", prompt(t, c), Turns("committed",
		Write("w1", "data/users.json", bad),
		Bash("b1", "git add data/users.json && git commit -q -m 'add user 3'"),
		Bash("b2", "sr-session refs track"),
	))
	e.Run(proj, "s-053-05a", "continue", Turns("fixed",
		Write("w2", "data/users.json", good),
		Bash("b3", "git add data/users.json && git commit -q -m 'give user 3 an email'"),
	))
	wantPass(t, e, c, proj, "s-053-05a")

	proj = project(t, e, c)
	e.Run(proj, "s-053-05b", prompt(t, c), Turns("committed",
		Write("w1", "data/users.json", bad),
		Bash("b1", "git add data/users.json && git commit -q -m 'add user 3'"),
		Bash("b2", "sr-session refs track"),
	))
	wantFail(t, e, c, proj, "s-053-05b", "a bad committed file left as it is")
}

// T053_06: citation — the uncited commit is refused; the cited one resolves.
func TestT053_06_Citation(t *testing.T) {
	const c = "citation"
	quote := "Raise request_timeout_seconds in limits.yaml from 30 to 60"
	e := newEnv(t)
	proj := project(t, e, c)
	e.Run(proj, "s-053-06a", prompt(t, c), Turns("done",
		Write("w1", "limits.yaml", "request_timeout_seconds: 60\nmax_retries: 3\n"),
		Bash("b1", "git add limits.yaml && git commit -q -m 'raise the timeout'"),
		Bash("b2", "git add limits.yaml"),
		Bash("b3", "git commit -q -m 'raise the timeout' -m 'Sloprail-Cites-User: "+quote+"'"),
	))
	wantPass(t, e, c, proj, "s-053-06a")

	proj = project(t, e, c)
	e.Run(proj, "s-053-06b", prompt(t, c), Turns("done",
		Write("w1", "limits.yaml", "request_timeout_seconds: 60\nmax_retries: 3\n"),
		Bash("b1", "git add limits.yaml && git commit -q -m 'raise the timeout' -m 'Sloprail-Cites-User: the user never said this'"),
	))
	wantFail(t, e, c, proj, "s-053-06b", "a trailer whose quote resolves nowhere")
}

// T053_07: skill-required — the write is refused until the skill was read.
func TestT053_07_SkillRequired(t *testing.T) {
	const c = "skill-required"
	e := newEnv(t)
	proj := project(t, e, c)
	e.Run(proj, "s-053-07a", prompt(t, c), Turns("done",
		Write("w1", "memories/idea.md", "# an idea\n"),
		Skill("s1", "authoring-guardrails"),
		Write("w2", "memories/idea.md", "# an idea\n"),
	))
	wantPass(t, e, c, proj, "s-053-07a")

	proj = project(t, e, c)
	e.Run(proj, "s-053-07b", prompt(t, c), Turns("done",
		Write("w1", "memories/idea.md", "# an idea\n"),
	))
	wantFail(t, e, c, proj, "s-053-07b", "a refusal never recovered from")
}
