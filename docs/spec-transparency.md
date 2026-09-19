# Spec transparency — making the intent→formalism mapping reviewable

Companion to `verification-contracts.md`. That note establishes that all
residual risk concentrates in the specification. This one is about the
consequence: if the human's only job is signing off intent, the mapping from
human meaning to formal object must be *legible*, and the gaps in it must be
*surfaced mechanically*.

Status: process design, untested. Written to be argued with.

---

## The framing that makes this tractable

The reviewer is not checking that the formalism is correct. They are checking
that it **says what they meant**. Those are different tasks and want different
artifacts.

Checking correctness of a quantified formula is hard and unreliable. Checking
that a concrete instance matches an intention is easy and reliable. Every
technique below is a move from the first to the second.

---

## The transparency ladder

Cheapest first. Each level is independent; adopt what earns its place.

### 1. Comments

Necessary, and the weakest link. Unchecked, so they drift — and a plausible
comment over wrong logic is worse than no comment, because it manufactures
confidence. Use them; never rely on them.

### 2. Traceability — identifiers both ways

Every prose clause gets an identifier. Every formal obligation cites one.

```
INTENT-TRF-03: A rejected transfer must leave all balances unchanged.
```
```lean
/-- INTENT-TRF-03 -/
theorem rejection_is_pure : ...
```

Two checks become mechanical, both `ε = 0` (grep, not judgment):

- every intent clause is cited by ≥1 obligation — **uncovered clauses**
- every obligation cites a clause — **unreviewed scope creep**

Highest value per unit of effort on the ladder. Adopt this one first.

### 3. Named semantic units

Do not let logic be a wall of nested conditionals. Name each condition in the
vocabulary of the domain:

```lean
def accountExists   (l : Ledger) (a : AccountId)          : Prop := (l a).isSome
def validAmount     (amt : Int)                           : Prop := amt ≥ 1
def sufficientFunds (l : Ledger) (a : AccountId) (amt : Int) : Prop := ...
def distinctParties (f t : AccountId)                     : Prop := f ≠ t
```

The decision structure then reads as business rules rather than control flow.

**The real argument is not readability.** Naming the units is what makes a
*missing* unit visible: `distinctParties` has no source clause, which is how the
self-transfer defect surfaced. Units are the spec's vocabulary — a distinction
you do not name is one the formalism cannot make.

### 4. Executable examples — the sign-off surface

```lean
example : transfer l₀ alice bob 30 = (l₀[alice ↦ 70][bob ↦ 80], .ok 70) := by decide
```

`by decide` means the checker confirms the example. So the reviewer reads
arithmetic, not theorems, and the examples cannot lie.

This is the practical core of transparent sign-off. The formalism stays; the
review surface becomes instances.

### 5. Round-trip rendering

Generate prose back from the formal structure — "rejected when: the account
does not exist, or the amount is not positive, or funds are insufficient" — and
diff against the original intent. Proves nothing, but differences are cheap to
spot and it catches silent scope change on re-verification.

### 6. Adversarial implementations, kept as documentation

Maintain a checked-in list of deliberately wrong implementations the spec is
known to reject: always-deny, grant-without-debit, self-transfer-minting.

A reviewer learns more from what a spec *catches* than from what it says.

### 7. Decision tables where logic is branchy

| exists(from) | exists(to) | validAmount | sufficient | distinct | → |
|---|---|---|---|---|---|
| ✗ | – | – | – | – | 404 |
| ✓ | ✗ | – | – | – | 404 |
| ✓ | ✓ | ✗ | – | – | **?** |
| ✓ | ✓ | ✓ | ✗ | – | 409 |
| ✓ | ✓ | ✓ | ✓ | ✗ | **?** |
| ✓ | ✓ | ✓ | ✓ | ✓ | 200 |

Exhaustiveness over `n` named units is mechanical (`2^n` rows, blanks flagged).
Nested conditionals hide unhandled combinations; a table makes them impossible
to overlook.

**Recommended baseline: levels 2, 3 and 4 together.** 5–7 where logic is dense.

---

## Deriving the named units

Unit extraction is **partly mechanical, partly heuristic**, and the split
determines where a human is genuinely required.

### Mechanical — from the formal document

These fall out of an interface description with no judgment:

| Source | Yields |
|---|---|
| Schema constraints (`minimum`, `maxLength`, `enum`, `required`) | validity units |
| Declared error responses | one precondition unit per error |
| Path and query parameters | existence/lookup units |
| Type nullability | presence units |
| Auth requirements | authorisation units |

A generator can produce these reliably. They are the spec restated, not
extended.

### Heuristic — from knowledge outside the document

This is where the gaps live, and where the human's real work is. Sources worth
mining explicitly rather than hoping someone remembers:

**Domain vocabulary and existing models.** Glossaries, database schemas,
existing type definitions, event catalogues, ubiquitous-language documents. A
noun in the domain that has no corresponding unit is a candidate gap. A
constraint enforced by a database (unique index, check constraint, foreign key)
that appears nowhere in the spec is a *certain* gap — it exists, it is load-
bearing, and the formal description is silent on it.

**A standing catalogue of recurring units.** These repeat across domains, and
checking a new spec against a standing list is far closer to mechanical than
inventing from scratch:

- aliasing / self-reference (`from == to`) — caught the transfer defect
- conservation of a total
- idempotence under retry
- monotonicity (counters, versions, timestamps)
- boundary at zero, one, and empty collection
- ordering and tie-breaking
- absence: what happens when an optional thing is missing
- concurrency: two callers, same resource
- authority: who is allowed to do this at all

**Adjacent artifacts.** Prior incidents and postmortems (each names an invariant
that was violated), existing test suites (each test encodes an assumption),
runbooks, support tickets, regulatory or audit requirements. All of these
describe behaviour the formal document omits.

**Adversarial generation.** Ask an agent for implementations that satisfy the
current unit set but that a human would reject. Each success is a *witness* —
a concrete program proving the spec is too weak, with the missing unit readable
off it. Sound checker, weak generator: a false witness costs only tokens, and
the only thing that reaches the human is a program that genuinely verifies.
This is the one place where aggressive retry is desirable, because finding the
blind spot *is* the deliverable.

### What is checkable about a unit set, even though its generation is not

You never have to trust that the set is complete. You get told,
deterministically:

- **exhaustiveness** — blank cells in the table
- **traceability** — units citing no clause, clauses citing no unit
- **load-bearing-ness** — drop a unit, re-verify; if nothing breaks it was inert
- **vacuity** — can `false` be derived from the preconditions; is each
  postcondition reachable
- **mutation survival** — flip `≥` to `>`, swap `old(self)` for `self`, drop a
  conjunct; if everything still verifies, that clause constrained nothing

Missing units surface *indirectly* — as an obligation that will not prove, or
an example nobody can complete. That indirection is fine. It is still a
mechanical signal.

---

## The applied pipeline

Run before any agent is dispatched. Input: a formal interface document plus
whatever external sources exist. Output: a question list for the spec author.

1. **Extract intent clauses**, one identifier each, from the document only.
2. **Name the semantic units** — mechanical ones from the document, heuristic
   ones from domain vocabulary, the standing catalogue, and adjacent artifacts.
   Mark every unit with no source clause.
3. **Build the decision table** over the units. Flag blank cells.
4. **Run traceability** both directions. Flag uncovered clauses and uncited
   obligations.
5. **Write executable examples**, one per clause. Flag any that cannot be
   completed.
6. **Run adversarial generation** within a fixed budget. Collect verified
   witnesses.
7. **Emit the question list.** Every flag from 2–6 becomes a numbered query.

### Worked result — the transfer endpoint

Five clauses in (shape and status codes only), five queries out:

```
QUERY-01  Which balance does 200 return — sender's or recipient's?
QUERY-02  Is from == to permitted? No-op, or error?
QUERY-03  What is returned for amount < 1? 400 is implied but undeclared.
QUERY-04  Confirm: 409 and 404 leave all balances unchanged.
QUERY-05  Confirm: total balance across accounts is invariant.
```

Two of these are genuine defects rather than pedantry. None required anyone to
have thought of them in advance.

**The artifact for human sign-off is this question list, not the formalism.**
It is mechanically derivable from unfilled cells, uncompletable examples,
untraceable obligations and verified witnesses. Judgment is required to
*answer*, never to *find*.

---

## Where this sits in the architecture

- Runs **before dispatch**, as a gate on contract sign-off.
- Answers land via the orchestrator's `AmendSpec` path.
- Bar for proceeding: no unanswered queries, and an adversarial pass producing
  no accepted witnesses within budget. Absence of witnesses is not proof of
  adequacy — but it is measurable and budgetable, which "the spec looks
  complete" is not.
- Cheapest possible place to catch a defect: one question here versus a
  silently divergent implementation later.

---

## Honest limits

- Unit generation is heuristic and stays heuristic. The catalogue and the
  external sources narrow it; nothing closes it.
- Independent re-derivation (a second agent specs the same prose, blind) finds
  disagreement, which marks ambiguity in the prose. Agreement proves nothing —
  both may misread identically.
- Unstated requirements remain invisible. Nothing surfaces a property nobody
  anywhere wrote down.
- Modelling choices leak silently: anything outside the formal model (wall-clock
  time, concurrency, serialisation) is tested rather than proved, and the spec
  quietly says less than it appears to. State the model boundary explicitly as
  part of sign-off.

---

## Open

- [ ] Does the standing catalogue live per-project or per-organisation? It is
      the accumulated knowledge asset here, and it improves with every incident.
- [ ] What budget makes an adversarial pass meaningful? Zero witnesses in ten
      attempts says little; in a thousand, more.
- [ ] Can database constraints be diffed against the unit set automatically?
      That is a mechanical gap-finder hiding in an artifact most teams already
      have.
- [ ] Who answers the question list when the spec author is the supervisor
      agent rather than a human?
