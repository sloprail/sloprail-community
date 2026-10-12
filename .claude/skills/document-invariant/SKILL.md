---
name: document-invariant
description: Use when judging or writing an invariant — the atomic domain rules a spec asserts. What a GOOD invariant IS: an always-true, field-anchored statement of a domain truth. Reused by the spec-quality checks AND the authoring agent.
---

# Document Invariant

An invariant is one always-true rule about the domain's data. Invariants are the "physics" of the
spec: they combine by AND — the spec is consistent only when every one holds at once. An invariant
has a `name` (its id) and a `predicate` (the rule). Nothing else is judged.

## Unstated is unconstrained

A spec need not be complete. Each invariant states its own boundary, a mechanical condition
saying which inputs it covers, and what holds there, in one or two sentences. On an input no
invariant covers, any output is acceptable and nobody may refuse it: "no invariant decides X" is
never a defect of the spec, and never a reason to add a clause. What IS stated must be rigorous:
a boundary two readers apply alike, and a rule two readers read alike inside it.

- ❌ a clause added to close a case another reader might ask about (`…, except in R of cd D || R,
  and a call of a function defined on the line, and …`): each exception is one more boundary to
  argue
- ✅ `Right after an {@ent:line:Invocation} whose {@fld:line:Invocation.bin} is cd and whose one
  operand's {@fld:words:Word.value} is an absolute path, the {@fld:line:Scope.cwd} is that path,
  lexically cleaned.`
  (a cd with two operands, or `cd -P`, is unstated: free)

## The rules

### An invariant states a domain truth, not an implementation mechanism

The predicate states WHAT is always true about the data, not HOW the code keeps it true. The test:
could someone who has never seen the codebase — only the domain — state and check this rule? If yes,
it's a domain truth. If it only makes sense to someone reading the implementation, it's a mechanism.

Reject a predicate ONLY when its subject is a named code artifact — a specific SQL/ORM operation
(`upsert`, `INSERT … ON CONFLICT`) or a code path (an HTTP route, a named query/function/handler,
"the SELECT"). Everything else is a domain truth. In particular do NOT reject a predicate for how it
phrases the outcome: an action, an actor's role, a state change, retention, visibility, or "hidden
from / found by / listed in / stored as" are all valid ways to state a data fact — they describe
WHAT holds about the data, which any domain expert can check without reading the code.

- ❌ `Re-recording an existing Session leaves its autopilot_enabled unchanged.` (subject is a SQL upsert)
- ❌ `The GET /orders endpoint never returns a cancelled order.` (subject is a code path)
- ✅ `A Session's {@fld:session:Session.autopilot_enabled} changes only by an explicit toggle.`
- ✅ `A User's {@fld:user:User.role} changes only when the acting user is an admin.` (action + actor)
- ✅ `A soft-deleted {@fld:user:User.deletedAt} User is excluded from active-member listings.` (visibility)

### An invariant must be violable and matter

The system must be able to plausibly get it wrong, and it must matter when it does. If negating the
predicate is meaningless, it only restates the schema (an enum value, a foreign key) and is not an
invariant — do not author it.

- ❌ `A SessionFolder points at an existing session.` (a foreign key; "points at a non-existent session" is impossible by construction)
- ❌ `A session's spec clone is the SessionFolder whose role is spec.` (restates the role enum)
- ✅ `A cancelled {@fld:order:Order.status} is reachable only from pending or confirmed.` (the system could get this wrong; it matters)

### An invariant is always-true, not a sequence of steps

State a condition that holds at all times. "When X, Y", "After X, Y", or a value fixed "as of" /
"at" some point (`the total as of order creation`) are all FINE — they state a condition and its
always-true consequence. Reject ONLY a predicate that narrates a runtime ORDERING of internal
operations (`until`, `advances after`, `then step N runs`) with no data condition.

- ✅ `An {@fld:order:Order.total} equals the item sum as of order creation.` (a fixed-point fact, always true)
- ❌ `base_ref advances only after the checks pass, and not until the tree is clean.` (narrates a runtime sequence)

### A predicate must anchor on a real domain construct via a typed mention

Every predicate names at least one real field `{@fld:domain:Entity.field}` or entity
`{@ent:domain:Entity}`. Anchor on a field when the rule is about a value; on an entity when the rule
is about a relationship between entities. Untyped text like `Product.active` is not a reference; the
target must already exist.

- ✅ `An inactive Product {@fld:catalog:Product.active} is not visible to customers.` (a value rule)
- ✅ `Every {@ent:order:Order} has exactly one {@ent:notification:Notification}.` (a relationship rule)
- ❌ `An inactive product is hidden from customers.` (no typed anchor — name the field: `{@fld:catalog:Product.active}`)

### Everything a predicate constrains or reads is a typed mention, under one name

Not only the anchor: every entity and every field the predicate constrains or reads is written as
its mention where the predicate first refers to it, and never under another name: no synonym, no
paraphrase, no plain `Entity.field`. Once the mention is written, the predicate may refer to the
same thing again by its own name (`its kind`, `the value`); a different wording is a synonym. A
reader, and a check, must see which value is meant without guessing whether "the directory a cd
sets" and `{@fld:shell:Scope.cwd}` are the same thing. A value the predicate relies on that no field holds is
a field the entity model is missing: add it to the entity it belongs on (document-entity), then
mention it.

- ✅ `After a cd, the {@fld:shell:Scope.cwd} is the directory it names.`
- ❌ `After a cd, the directory a cd sets is the one it names.` (a synonym — write `{@fld:shell:Scope.cwd}`)
- ❌ `After a cd, the Scope.cwd is ...` (a plain name — write `{@fld:shell:Scope.cwd}`)
- ❌ `After umask 077, the file mode mask is 077.` (no field holds the mask — add one to the entity, then mention it)

### An invariant is concrete: its inputs are bounded and no word can be stretched

A predicate covers a space of inputs a reader can enumerate: a named grammar, standard, enum or
listed set, defined once in the spec (an entity, or a field's `constraint_expr`) and referenced,
never "any valid X", "something that may …", "such as" or "etc." over an open-ended space. Every
term it uses is defined by the spec or by the standard it names, and every list in it is closed.
An invariant draws its own boundary: a mechanical condition saying which inputs it covers; it
need not be complete, and what lies outside it is unstated. The test: for a given input, can
two readers agree whether the predicate covers it and what it requires? If a
judge can always build a new, more exotic input the wording seems to reach, the invariant never
converges: in one eval, "a Line whose text is valid shell syntax has no parseError" was refused
in 24 of 31 judged rounds, nearly each time for a new line (`export A &>out B`, `echo ${x.$(a)}`,
`declare -a a=(x\;y)`), because "valid shell syntax" named no grammar.

- ❌ `A {@ent:line:Line} whose {@fld:line:Line.text} is valid shell syntax has no {@fld:line:Resolution.parseError}.` (valid in which shell? bash accepts lines no parser reads alike)
- ✅ `A {@ent:line:Line} whose {@fld:line:Line.text} is written in the {@ent:line:Grammar}, nested at most two deep, has no {@fld:line:Resolution.parseError}.` (the Grammar entity names POSIX.1-2017 XCU 2 plus a closed list of bash extensions, each in a given form)
- ❌ `A {@ent:variables:Variable} has no value after something the line cannot follow may have changed it: read, arithmetic naming it, …` ("something … may have" and "arithmetic" reach every arithmetic context bash has)
- ❌ `After a call of a function whose body contains a cd, …` ("contains a cd" reaches `$c /a`, `{cd,/a}`, `eval 'cd /a'`)
- ✅ `After a call of a function whose body yields an {@ent:line:Invocation} whose {@fld:line:Invocation.bin} is cd, …` (decided by a field the spec defines)

A term several invariants rely on ("assigned", "a call", "the scopes a reference sees") is
defined once, in an entity, a field's doc or enum, and every invariant that uses it cites that
definition. It is not re-worded in each predicate, and not left to a standard that has several
overlapping notions of it: each re-wording is a new place where judges draw the line apart.

- ❌ `An export NAME of a {@ent:variables:Variable} the line assigned, …` (judges ruled `$((FOO))` is not assigning, `$((FOO=1))` is, and `unset` neither, in different rounds)
- ✅ `Right after a {@ent:variables:Change} whose {@fld:variables:Change.kind} is assignment, …` (the kind enum defines each form it names once; a form it does not name is outside the boundary)

Bounded inputs are not enough: an invariant asks only for what a program can decide. Where the
predicate requires a value the system computes by following the domain's own rules, and those
rules feed into themselves (code inside code, loops, recursion, references to references), the
predicate states where exactness stops: its boundary leaves out what lies past that point (which
is then unstated), or it says what is reported there, by a closed, checkable rule, never "absent
when it cannot be known". The
test: could someone write a program that, for every input the predicate covers, finishes and
meets it, without being an interpreter of the domain? A 40-character line
(`s='eval "$s"'; eval "$s"`) can denote a computation that never ends; a cut-off the spec does
not state is a fresh violation in every round.

- ❌ `A {@ent:command-strings:CommandString} whose text is known yields the Invocations its text holds, read by the same rules as a Line.` (a self-feeding string needs an interpreter run to its end)
- ✅ `A {@ent:command-strings:CommandString} has a {@fld:command-strings:CommandString.text} only when its {@fld:command-strings:CommandString.depth} is at most 8; …` (past the bound it has no text, and the spec's "no text" invariants say what is reported)
- ❌ `After a while, a Variable has a value only when every path through it leaves it with the same one.` (a loop's paths are unbounded)
- ✅ `At the start of a while, until or for, each Variable a Change in it names has no value up to its first Change there.` (the body is read once, from a defined state)

A named grammar is bounded only when the spec lists what it covers: a predicate or entity that
defers to a reference implementation ("as bash does", "by bash's escapes", "what `bash -n`
rejects") reaches every corner of that implementation's source, and a judge who cannot run it
argues each one from memory. A predicate that quantifies over the grammar's sentences (every one
of them read, every command in them reported) also limits how deep they nest or combine.

- ❌ `` A `$'…'` stretch contributes its decoded text to {@fld:words:Word.value}, by bash's ANSI-C escapes. `` (the escape set is whatever bash's source does)
- ✅ `` In a `$'…'` stretch, each escape of {@fld:line:Grammar.ansiCEscapes} contributes the character its entry names to {@fld:words:Word.value}, and a backslash that starts none of them contributes itself. `` (a closed table in the spec)
- ❌ `A {@ent:line:Line} that is not written in the {@ent:line:Grammar} has a {@fld:line:Resolution.parseError}.` (every text bash's parser rejects, at any depth)
- ✅ `A {@ent:line:Line} written in the {@ent:line:Grammar} but at one place, where it shows one of {@fld:line:Grammar.faults}, nested at most two deep, has a {@fld:line:Resolution.parseError}.` (a closed list of faults, a bounded depth)

### At most one invariant decides an operation's effect

For a value that evolves along the input (a variable's value, the current directory, what is
exported), an operation's effect on it is decided by at most one invariant. Two invariants that
both cover one input and decide its effect are an overlap: a conflict when they differ, a
duplicate when they agree; one cites the other instead. An operation decided by none is a gap,
and a gap is fine: its effect is unstated.

- ❌ `unset NAME empties the {@fld:variables:Variable.value}` and `a Variable keeps its {@fld:variables:Variable.value} until a plain assignment` (both cover `X=1; unset X; echo $X`, and differ)
- ✅ `Right after a {@ent:variables:Change} of kind unset, the Variable it names has the empty string as its {@fld:variables:Variable.value}.` (one owner; what `read X` does may be stated by another invariant, or by none)

### A single-value field bound is a constraint_expr, not an invariant

A length, range, format, or enum membership on one field's own value lives on the field
(`constraint_expr`/`enum`) — see document-entity. Author an invariant only for uniqueness or a rule
spanning MULTIPLE fields/entities that no single field can express.

- ❌ invariant `name is 1..120 chars` → belongs as `constraint_expr: len 1..120` on the field
- ✅ invariant `A Product's {@fld:catalog:Product.reservedInventory} never exceeds its {@fld:catalog:Product.inventory}.` (two fields)
