# Verification as the backbone — formal notes

Companion to the agentic dev environment draft. Where that document argues the
architecture, this one states the part that can be made precise, so the design
rules follow from something rather than being asserted.

Status: derivation, not implementation. Written to be argued with.

---

## The claim being formalised

> What made AlphaProof work was Lean: deterministic, cheap, and impossible to
> persuade.

Three properties, each independently load-bearing. Let `S` be specifications,
`I` implementations, and

```
V : S × I → {accept, reject}
```

1. **Determinism.** `V(s,i)` is a function. Same inputs, same verdict, always.
2. **Invariance under semantically-null perturbation.** For any decoration `d`
   — comments, README text, log lines, dependency metadata, an issue body —

   ```
   V(s, i⊕d) = V(s, i)
   ```

   This is the precise content of "impossible to persuade". Text that does not
   change the artifact's meaning cannot change the verdict. Lean has this. An
   LLM judge does not: `π(h⊕d) ≠ π(h)` is exactly what prompt injection
   exploits.
3. **Error independence.** `V`'s failures are uncorrelated with the
   generator's. When checker and producer are the same model, errors
   concentrate precisely where the generator's mistakes live.

Property (2) is the one the threat model needs. A confused-deputy attack *is* a
null perturbation: the code is what it is, and the attacker's leverage is the
surrounding text.

---

## The probability model

Two events over a single artifact:

- `C` — the artifact is correct. `P(C) = q`.
- `A` — the checker accepts it.

Two parameters, one per conditioning branch:

- `p = P(A | C)` — sensitivity. False-negative rate is `1 - p`.
- `ε = P(A | ¬C)` — **false-accept rate. The persuadability parameter.**

### Full group of events

The exhaustive partitions are *within* each condition, not across them:

```
P(A|C) + P(R|C) = 1
P(A|I) + P(R|I) = 1
```

`P(A|C) + P(R|I)` sums to 2 for an ideal classifier — the two terms live in
different conditioning universes and cannot be added.

The genuine joint distribution:

```
P(C,A) = q·p              true accept       — work done
P(C,R) = q(1-p)           false reject      — work wasted
P(I,A) = (1-q)·ε          false accept      — THE DANGEROUS CELL
P(I,R) = (1-q)(1-ε)       true reject       — work correctly stopped

sum = q + (1-q) = 1
```

Marginalising over correctness (summing the Accept column) gives

```
P(A) = q·p + (1-q)·ε
```

### The posterior

```
P(¬C | A) = (1-q)ε / (q·p + (1-q)ε)
```

which is just *false accepts / all accepts*. Dividing through by `(1-q)ε`:

```
P(¬C | A) = 1 / (1 + [q/(1-q)] · [p/ε])
```

So the whole model is two quantities: **prior odds** `q/(1-q)` and **likelihood
ratio** `p/ε`.

### Extremes

| Condition | Result | Meaning |
|---|---|---|
| `ε → 0` | posterior → 0 for any `q > 0` | **A weak generator plus a sound checker is a sound system.** AlphaProof. |
| `ε = p` | posterior = `1-q` | Acceptance is uninformative. The checker told you nothing. |
| `q → 0`, `ε` fixed | posterior → 1 | Rare correctness swamps a leaky verdict. |

### Sensitivity: why `ε` is the only dial that matters

At `q = 0.7`, `p = 0.95`:

| `ε` | `p/ε` | `P(¬C\|A)` |
|---|---|---|
| 0.001 | 950 | 0.045% |
| 0.01 | 95 | 0.45% |
| 0.05 | 19 | 2.2% |
| 0.2 | 4.75 | 9.2% |
| 0.5 | 1.9 | 22% |

Roughly linear in `ε` while `ε` is small: **halving the false-accept rate
halves bad merges.** By contrast, at `ε = 0.05`, dropping `p` from 0.95 to 0.60
moves the posterior only from 2.2% to 3.4%. A checker that rejects 40% of good
work barely affects the trustworthiness of what it accepts.

**Corollary: trade `p` away for `ε`.** Stricter contract tests that
occasionally reject conforming implementations are a good deal. Better agents
are expensive; a stricter check is cheap.

### The geometry

`p` and `ε` are separately specifiable — knowing one tells you nothing about
the other. A classifier is a point in the unit square `(ε, p)`:

```
p=1  (0,1) IDEAL ┌──────────────┐ (1,1) accept-everything
                 │        ╱     │
                 │     ╱  diagonal p = ε: zero information
                 │  ╱           │
p=0  (0,0) ──────┴──────────────┘ (1,0) perfectly inverted
     ε=0                      ε=1
```

- Distance from the diagonal is **discriminating power** — an engineering
  property, expensive to improve.
- Position along the curve is **bias** — a threshold choice, free.
- Adversarial pressure moves you **rightward**, toward the diagonal. A judge
  benchmarked at `(0.05, 0.95)` on benign input may sit at `(0.4, 0.95)` under
  attack: same `p`, far less informative.

Quoting `p` alone characterises nothing. "Our suite passes 95% of good builds"
is not a quality claim.

---

## Why an unreliable checker degrades under load

The single-draw model assumes one i.i.d. attempt. Agents retry. What survives
is the *first acceptance*, so over `N` attempts against an incorrect artifact:

```
P(ships something incorrect) ≈ 1 - (1 - ε)^N
```

At `ε = 0.05`, ten attempts gives ≈40%. The per-artifact 2.2% is not the number
you live with.

Worse, `ε` is not constant across attempts. The agent conditions on each
rejection, so attempt `k+1` is drawn nearer the checker's error region:

```
ε_k = P(A | ¬C, k prior rejections)    non-decreasing for an optimising generator
```

This is Goodhart stated as a conditional probability, and it is the formal
reason a persuadable checker **gets worse the harder the agents work**.

Two consequences:

- **Retry budgets are a soundness parameter, not a cost control.** The cost
  ceiling question is a correctness question wearing a cost disguise.
- **False negatives convert into false-positive risk.** A flaky test does not
  merely waste tokens: to an agent, red means *change the code*, so a flaky
  check is an instruction to modify working code until something passes. CI
  must therefore distinguish infrastructure failure from contract failure, so
  the supervisor can re-run rather than dispatch a retry.

---

## Typing the design rules

Stated as rules, they are persuadable. Stated as types, they are
unrepresentable.

```
accept : Artifacts → Verdict            -- no AgentClaim in the domain
```

Override is not forbidden; it cannot be expressed. Same move as the generated
client: the frontend cannot call a nonexistent endpoint because no such method
exists.

```
Action = Decompose | Sequence | AmendSpec | Escalate | Halt
π : History → Action                    -- no Accept constructor
```

"The supervisor must not verify correctness" becomes a fact about its type.

### Decision procedure for placement

For each duty, ask: *does a total, cheap `V` exist whose input is the artifact
rather than a description of it?*

| Duty | Oracle? | Assign to |
|---|---|---|
| Compile, tests, contract tests | yes | CI |
| Schema / spec conformance | yes | CI |
| Policy (no push to main, quotas, path limits) | yes | policy engine |
| Loop and stall detection | yes — counters | mechanise |
| Sequencing | yes, once dependencies declared — topological sort | mechanise |
| Decomposition | no | supervisor |
| Writing the initial contract | no | supervisor |
| Adjudicating the spec is wrong | structurally no | supervisor |

Much of the supervisor's job mechanises. "Noticing" a loop is a counter.

### The supervisor loop, every guard mechanical

```
loop:
  v ← CI.verdict(task)                  # fact, not opinion
  m ← metrics(task)                     # counters only
  match:
    v = pass                → advance(dag)
    m.escalations ≥ k       → AmendSpec          # underspecification signal
    m.no_progress ≥ t       → Halt(task)
    m.cost ≥ budget         → Halt(run)
    v = fail                → dispatch(retry)
```

No branch asks the supervisor whether anything is correct.

**`AmendSpec` is the dangerous action.** It writes to the thing `V` validates
against — the formal analogue of adding an axiom to make a theorem go through.
Spec amendments must sit outside the loop that benefits from them: human
sign-off, and invalidation of prior verdicts rather than grandfathering.

---

## The irreducible residual

`V` decides `i ⊨ s`. It cannot decide `s ⊨ intent`, because intent is not
formalised — if it were, it would be the spec.

```
P(ship wrong) = P(i ⊭ s) + P(i ⊨ s but s ⊭ intent)
```

A sound checker annihilates the first term and leaves the second untouched. It
does not reduce total risk to zero; it **concentrates all risk into the
specification**. This is why the supervisor's only irreducible duty is
adjudicating that the spec is wrong, and why human sign-off belongs at contract
approval rather than at merge.

---

## The `ε` ladder

Investment ordering. Every property moved leftward is permanently zeroed.

```
unrepresentable → compiler-enforced → proved → tested → reviewed
```

| Check | `ε` | Why |
|---|---|---|
| Type system, generated client | ≈0 | Structural — no judgment involved |
| Schema validation | ≈0 | Total function over the artifact |
| Contract tests derived from spec | small | Derived, not authored by the agent |
| Unit tests | bounded by coverage | Only sees what was anticipated |
| LLM review | large, adversarially unstable | Persuadable |

**Push checks up the ladder rather than adding more of the lower rows.** The
capital investment goes into making wrong things inexpressible, not into
catching them once expressed — which follows directly from `q` barely appearing
in the posterior once `ε` is small.

---

## Two delivery lines

Same skeleton, same actors. The difference is what `V` can decide and where the
residual lands.

### Line A — spec and contract

| # | Actor | Artifact | Verification | `ε` |
|---|---|---|---|---|
| 1 | Human + supervisor | Goal → decomposition | none | n/a |
| 2 | Supervisor | OpenAPI spec + DoD | **human sign-off** | judgment |
| 3 | Toolchain | Server interface + typed client | generator determinism | ≈0 |
| 4 | Agent (backend) | Implementation | compile | ≈0 |
| 5 | Agent (frontend) | Implementation | compile against generated client | **0** for shape |
| 6 | CI | — | contract tests from spec | small |
| 7 | CI | — | unit tests | bounded by coverage |
| 8 | CI | — | schema validation | ≈0 |
| 9 | Policy engine | — | branch, quota, path rules | 0 |
| 10 | Human | Merge | review | judgment |

Residual: behaviour the contract does not pin down. Endpoint exists, types
match, tests pass, semantics wrong.

### Line B — Rust with a verifier

| # | Actor | Artifact | Verification | `ε` |
|---|---|---|---|---|
| 1 | Human + supervisor | Goal → decomposition | none | n/a |
| 2 | Supervisor | Formal spec: `requires` / `ensures`, invariants | **human sign-off** | judgment |
| 3 | Toolchain | Types and traits from spec | generator determinism | ≈0 |
| 4 | Agent (impl) | Safe Rust body | compile + borrow check | **0** for memory safety |
| 5 | **Agent (proof)** | Proof hints, lemmas, loop invariants | SMT discharge | **0** modulo solver + encoding |
| 6 | CI | — | verification over all inputs | **0** vs spec |
| 7 | CI | — | tests | largely redundant |
| 8 | Policy engine | — | `#![forbid(unsafe_code)]`; impl agents cannot write specs | 0 |
| 9 | Human | Merge | **spec review only** | judgment |

Residual: the spec, entirely. Plus solver soundness and the Rust-semantics
encoding — small, shared, audited elsewhere.

### What differs

- **A new actor at step 5.** Line B splits implementation from proof. This is
  what makes it viable: discharging proof obligations is itself the
  weak-generator-plus-sound-checker shape, so agents can burn attempts freely.
- **Tests invert.** In A they carry real weight and hold your worst non-LLM
  `ε`. In B they are redundant for verified properties.
- **Human review shrinks and hardens.** A: spec, implementation, test adequacy.
  B: specification only, because everything downstream is zero relative to it.
- **Step 2 gets harder in B.** A formal spec is longer and denser to sign off
  than OpenAPI plus DoD prose. This is the real cost and the honest reason not
  to start there.

### Retry dynamics — the operational difference

In A, a failing test invites search toward the checker's blind spots, and `ε_k`
rises with attempts.

In B there is no blind spot to search toward: no code fails `ensures` yet
verifies. Retries are therefore **safe** — the worst outcome is cost, not a bad
merge.

One exception, closed by policy in both lines: the agent weakens the postcondition
(B) or deletes the failing test (A) until it passes. Spec and test files must be
unwritable by implementation agents. A filesystem permission, not an instruction.

---

## Placement

- **Line A** wherever the spec churns; and for the POC regardless, since it
  tests the layering at a fraction of the setup cost.
- **Line B** where the spec is stable enough to amortise. The binding
  constraint is not difficulty but the ratio of specification cost to
  implementation cost: favourable for parsers, allocators, protocols, anything
  handling money; unfavourable where spec ≈ implementation and changes weekly.
- **Note the agentic inversion.** Formalisation cost is one-off; implementation
  cost recurs per change. If generating implementations is nearly free, domains
  where spec ≈ implementation may be exactly where you specify once and let the
  generator burn attempts. The conventional economics were derived before
  cheap generators.
- **Hybrid is likely the real answer.** A's contract at the service boundary,
  B's verification inside components where correctness is subtle. `ε` is a dial
  per property, not one choice for the whole factory.

---

## The research-grade bet

Pipelines pairing Rust verifiers with AI provers exist because proof obligations
are precisely where a weak generator plus a sound checker compounds — AlphaProof
one level down. If agents can discharge proof obligations reliably, specification
cost falls and the domain constraint above weakens considerably.

So the ambitious version is not "build the factory in Rust". It is:
**let the agents write the proofs, not just the code.**

---

## Open

- [ ] What is the measured `ε` of a contract-test suite derived from an
      OpenAPI spec? Everything above treats it as "small" without a number.
- [ ] Invariance is testable: inject adversarial text into comments, READMEs
      and log output, re-run CI, assert the verdict is unchanged. Add to
      milestone 5 alongside the drift check.
- [ ] Does `AmendSpec` invalidate prior verdicts, or grandfather them? The
      answer determines whether mid-run contract versioning is safe.
- [ ] Who may write to the decision log, and what belongs in it? Redundant
      re-litigation is machine-checkable only against what was written down.
