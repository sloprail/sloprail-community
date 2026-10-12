---
name: document-entity
description: Use when judging or writing an entity — a domain noun (User, Order, Product) and its fields. What a GOOD entity IS: domain concepts with typed fields, value constraints, and docs that DEFINE rather than rule. Reused by the spec-quality checks AND the authoring agent.
---

# Document Entity

An entity is a domain-layer concept the spec talks about; its fields are what invariants reference.
An entity has a `name`, an `emoji`, `fields`, and an optional `doc`. Each field has a `type` and, all optional,
a value constraint (`constraint_expr` and/or `enum`) and a `doc`. Structure (names, types) is
enforced by spec.cue — the rules below judge only MEANING, not presence.

## The rules

### A field carries a domain fact, not a storage artifact

A field belongs in an entity only if it is a fact about the domain concept. Storage/security
artifacts (`passwordHash`, salts, internal ids, cache keys) are NOT domain fields — omit them
entirely, even if the DB column exists.

- ❌ `passwordHash: string` (a security/storage detail, not a domain truth); ❌ `internalCacheKey: string`
- ✅ `email: string`; ✅ `role: string`

### A value constraint lives in constraint_expr or enum, not prose

Narrow a field's value space on the field itself. A fixed value set is the `enum` array; any other
narrowing (`len 1..120`, `matches email`, `>= 0`, `unique`, `uppercase`) is a short human-readable
`constraint_expr` — it need not be a formal executable expression. Do not restate the narrowing as
English elsewhere, and do not reject a constraint for being prose. A value's canonical form
(lowercased, uppercased, hashed, trimmed) IS its domain value, not a forbidden storage detail.

- ✅ `sku: string [unique, uppercase]`; ✅ `role: string enum: [admin, member, viewer]`
- ❌ a doc that says "the email must be unique" instead of a `unique` constraint / an `email_unique` invariant

### An enum field is type string plus a separate enum array

A fixed value set is `type: string` with a separate `enum: [...]` array — NOT `type: enum`, which
spec.cue rejects.

- ✅ `status: string enum: [pending, confirmed, cancelled]`
- ❌ `status: enum ...`

### A reference to another entity is the field's type

Point at another entity by setting the field's `type` to that entity's name (`type: Product`,
cross-domain `type: catalog.Product`) — never via `constraint_expr`.

- ✅ `product: catalog.Product`
- ❌ `constraint_expr: "references the product catalog"`

### A doc defines the construct, never states a rule

Entity and field `doc` say what the thing IS; rules live in invariants, not docs. A concise doc is
fine when the field is self-evident.

- ✅ entity doc `A platform user.`; ✅ field doc `The user's login email.`
- ❌ field doc `The email. Must be unique and lowercased.`

### An absent value is decided by a closed rule

A field that may be absent to mean "unknown" says exactly when it is absent: by a closed list,
or by naming the invariants that make it absent. "When it cannot be known without running
something" is not a rule: someone can always know one step more by running it in their head.
A per-item field keeps its meaning when one source item yields several items: say which source
they share and whether each can have a value.

- ❌ `Variable.value: Its value at a point of the line; absent when it cannot be known without running something.`
- ✅ `Variable.value: Its value at a point of a Scope; absent exactly where an invariant of the variables domain says it has none.`
- ❌ `Word.text: The word as written.` (one written `$X$(c)` can yield several Words: which text, and can one of them have a value?)
- ✅ `Word.text: The written word it comes from; every Word one written word yields has its text.`

### An entity is a domain concept, not a wire format

An entity models a domain noun, not an HTTP request/response shape, a DB row layout, or an internal
struct.

- ✅ `Order`, `Product`, `Tenant`
- ❌ `CreateOrderRequestBody`, `OrdersTableRow`

### An entity exists once per domain

Do not author the same entity twice or duplicate it across domains. If two domains both need `User`,
defer the sharing decision rather than copying it.
