# Agentic dev environment — design draft

Status: draft, pre-implementation. Written to be argued with.

---

## The principle

> **The sandbox is the security boundary. The contract is the correctness
> boundary. The supervisor is the planning function. Never let one do another's
> job.**

Every design question below resolves against this. If a proposal blurs two of
the three, it's wrong regardless of how convenient it is.

---

## Why these three, separately

The three failure modes are different in kind, so conflating their solutions
produces a system that handles none of them well.

| Failure | Boundary | Enforced by |
|---|---|---|
| Agent reaches something it shouldn't | Security | Sandbox: filesystem, network, credentials |
| Agents build mutually incompatible things | Correctness | Contract + CI, deterministic |
| Work is decomposed badly or the plan is wrong | Planning | Supervisor agent, judgment |

The recurring mistake is asking an LLM to enforce correctness or security. An
LLM supervisor judging LLM workers is an unreliable checker over unreliable
producers — it does not compound into reliability. What made AlphaProof work
was Lean: deterministic, cheap, and impossible to persuade. A supervisor agent
has none of those properties.

**Corollary:** anywhere a machine-checkable rule can be written, write it and
enforce it deterministically. Reserve the agent for the work that has no
oracle.

---

## Layer 1 — Sandbox (security)

### One sandbox per crew, not per agent

The boundary that matters is **outward**. Nothing inside reaches host
credentials, host containers, or the network beyond an allowlist.

Agents inside a crew are **mutually trusted** — they're the same model, under
the same instruction, working on the same goal. A security boundary between
them protects against nothing and costs shared state.

> Note: an earlier version of this reasoning argued for a daemon per agent. That
> conflated *interference* (a workspace problem, cheap to solve) with *threat*
> (a security problem). Interference is handled in Layer 2.

### What the sandbox provides

- Private Docker daemon. Containers started inside do not appear in the host's
  `docker ps` — a real boundary, not a naming convention.
- Default-deny egress with an explicit allowlist.
- No host credential mounts: not `~/.aws`, not `~/.ssh`, not `.env`.
  Credentials stay outside and are injected as scoped, short-lived tokens if
  needed at all.
- Source mounted read-only where possible; a working copy inside otherwise.
- Disposable. Kill it and the cluster, branches, containers, and any mess go
  with it.

### Credentials: two options, and which works depends on the runtime version

**This section is version-dependent.** Option A worked on sbx 0.42.1 and is
blocked on 0.43.0. Option B works on both. Record the version alongside any
claim about the credential boundary.

#### What does not work in either case: the built-in service secret

The runtime's `anthropic` service is defined around an API key and writes the
credential as an `x-api-key` header. Subscription credentials are OAuth and
require a Bearer header plus an OAuth beta header. Measured against the live
endpoint:

| Headers sent | Result |
|---|---|
| `Authorization: Bearer` + OAuth beta header | authenticates |
| `x-api-key` | 401 |
| `x-api-key` + OAuth beta header | 401 |
| both credential headers together | 401 |

The last row matters: an otherwise-valid Bearer request is poisoned by the
presence of `x-api-key`. There is no arrangement in which the service secret's
header and a working OAuth request coexist.

#### Option A — custom secret, placeholder substitution (sbx ≤ 0.42.1)

A custom secret registers a target host, an environment variable name, and a
credential source. The runtime generates a placeholder, sets the environment
variable inside the sandbox to it, and substitutes the real value into outbound
requests to that host. The client writes its own headers; the proxy only swaps a
string — which is exactly why this survived where the service secret failed.

```
sbx secret set-custom \
  --host api.anthropic.com \
  --env CLAUDE_CODE_OAUTH_TOKEN \
  --placeholder 'sbx-cs-<pinned>' \
  --command 'security find-generic-password -s "Claude Code-credentials" -w \
             | jq -r .claudeAiOauth.accessToken | tr -d "\n"' \
  --refresh on-demand
```

Verified end to end on 0.42.1: the store held `command:...` rather than a token,
`sbx exec <sandbox> -- env` showed the placeholder, and the agent answered
prompts. The real credential existed only in the host keychain, and only in
flight.

Properties worth keeping in mind if this route returns:

- **`--command` beats `--value`.** `--value` and `--token` put the secret in
  shell history and process listings. `--command` stores only the recipe,
  resolved host-side by `sandboxd` at request time under `--refresh`
  (`on-demand`, or a duration). The trade: `sandboxd` gains standing access to
  the named keychain item.
- **Trim the output.** Command stdout is passed verbatim, so `jq -r`'s trailing
  newline lands inside the Bearer header and produces a clean 401 with
  everything else looking correct. `| tr -d "\n"` or `jq -j`. This does not
  arise with `--value`, where the shell strips it first — so the bug appears
  only on migrating to `--command`.
- **Pin the placeholder.** Without `--placeholder`, a delete-and-re-add mints a
  new value that no longer matches the sandbox's environment variable, forcing a
  recreate.

#### Option B — environment variable (works on 0.43.0)

```
ACC=$(security find-generic-password -s "Claude Code-credentials" -w \
      | jq -r .claudeAiOauth.accessToken)
sbx create --name <sandbox> -e CLAUDE_CODE_OAUTH_TOKEN="$ACC" claude .
```

The real token is in the sandbox environment. Any process there can read it,
including the agent acting on attacker-influenced input. Containment falls
entirely to the egress policy.

Environment variables are fixed at creation, so rotation means recreating the
sandbox, not updating it.

#### What changed in 0.43.0

The release hardened the egress proxy so that a client-supplied credential the
proxy did not issue is not forwarded to managed provider hosts. Substitution now
fails **silently**: no error at `set-custom`, no warning at creation, correct
placeholder in the environment, correct entry in the store, and a 401 at request
time. Verified on a freshly created sandbox, so it is not migrated state.

The companion change closes a real hole — a third-party kit re-declaring a
built-in agent's OAuth service to inherit that agent's trust without an explicit
binding. An operator-configured custom secret is structurally indistinguishable
from that attack at the proxy, which is the likely reason it was caught.

**Net effect on this design: the hardening made the credential boundary worse.**
The only supported path for a subscription credential now places it inside the
VM. The requested fix is an operator binding step on the placeholder — it is
already a generated, unguessable identifier mapped to a source and a target
host, so only an approval record is missing. Filed upstream.

#### Comparison

| | Option A (≤0.42.1) | Option B (0.43.0) |
|---|---|---|
| Real token in VM | no | **yes** |
| Agent can read it | no | **yes** |
| Rotation | automatic, `on-demand` resolve | manual, recreate sandbox |
| Secret in shell history | no (`--command`) | avoidable via `$(...)` |
| Containment mechanism | boundary + egress | **egress only** |

#### Credential source, either option

Use the short-lived access token from the host client, not a minted long-lived
one. Measured lifetime **~24 hours**, renewed *at* expiry rather than ahead of
it — so on failure, trigger a host-side refresh before re-reading. A minted
`setup-token` also works but is the wrong shape of risk: one year, no TTL
option, revocation only by per-token click in account settings (a list that
reached 27 entries after ordinary use). Tested: revocation is immediate and
effective — 429 before the click, 401 within a minute after.

The keychain item name and JSON shape are undocumented internals; re-verify
after client upgrades. On Linux the equivalent is `~/.claude/.credentials.json`.

#### CLI ergonomics worth knowing before an incident

- `set-custom` may refuse to overwrite an existing entry; delete first.
- `secret rm` identifies an entry by `--host` or `--placeholder`, not `--env`
  alone, and prompts `y/N` — so it cannot be pasted in a multi-command block
  without silently answering No.
- Both add and remove apply immediately to running sandboxes.
- `--command` runs through a shell, so pipes work without an `sh -c` wrapper.
- `sbx version`, not `sbx --version`.

#### Residual gaps

- The credential boundary is a moving target across runtime versions, and a
  regression in it failed silently. Any claim in this document about where the
  credential lives needs a version attached.
- An expired or refused credential presents as no progress or a login prompt,
  not an error.
- Under Option B, the credential's containment is the egress allowlist alone.
  Any entry that accepts arbitrary content — a git forge, an object store, a
  paste service, a webhook endpoint — converts an accident into a disclosure.
- Whether anything inside the sandbox writes a resolved credential to disk is
  untested.

### Egress policy: deny-all is the default posture

Default-deny with an explicit allowlist is a setup-time choice, and it is the
one to take. Anything unanticipated is then blocked and discovered by failure,
rather than permitted and discovered never.

Verified behaviour: with an allowlist of exactly one host (the model endpoint)
and everything else denied, the agent starts, authenticates and responds
normally. This is what makes the credential exception tolerable for the POC —
the token is readable inside the VM, but there is nowhere to send it.

**Kits contribute network rules you did not choose.** A sandbox's policy is the
union of local rules and rules supplied by the agent kit, scoped to that
sandbox, marked non-editable and reinstated at every create. The Claude kit
(sbx 0.43.0) opens seven Anthropic hosts: the API endpoint, three documentation
and platform sites, a downloads host, an MCP proxy, and a user-content bridge.
All Anthropic-operated, none third-party — but they are still reachable
destinations, and under Option B the sandbox holds a real credential. The egress
boundary is therefore not solely an operator artifact, and its contents change
with the kit.

Practical rules:

- Rules are policy-engine state, not agent state, and not part of the
  environment file. Check intent before creating anything (`policy check`), and
  confirm both directions: the allowed host resolves, a control host does not.
- Never add an allowlist entry without first seeing a denial for it in the
  policy log. An allowlist assembled from guesses cannot be defended; one
  assembled from observed denials can.
- Test more than one control host. A policy that blocks GitHub but leaks the
  package registry is a policy that leaks.

#### Opening GitHub is not a routine allowlist entry

Under Option B the sandbox holds a real, working credential in its environment.
The egress allowlist is then the *only* thing preventing that credential from
leaving. The eight hosts currently reachable are all Anthropic-operated and
none of them accept arbitrary attacker-chosen content. A git forge does.

Adding `github.com` therefore changes the token's blast radius by category, not
by degree — and it is the kind of change that gets made absent-mindedly, as a
side effect of "the crew needs to push somewhere", by an operator on the host
who is thinking about workflow rather than about credentials.

**The realistic failure is not malice.** Nothing needs to decide to exfiltrate:

- `env > debug.txt` while troubleshooting, then `git add -A`
- a stack trace or crash dump that includes the process environment
- a helpful "let me commit everything so we don't lose work"
- a CI log, artifact or issue comment echoing the environment

Any of these puts the token in a commit. On a public repository it is scraped
within minutes. Note that this is the *confused deputy* in its plainest form:
the agent is being helpful, and the resulting damage is identical to the
malicious case.

It is also the case the contract layer cannot help with. CI decides whether
code works; it has nothing to say about whether a commit contains a secret.
That is a policy question, which by this document's own argument must be
answered deterministically rather than by a watchful supervisor.

**Preferred: do not open it.** Gitea inside the sandbox already appears in this
design as the git remote for Argo CD to reconcile from without handing an agent
GitHub credentials. It serves a second purpose: it gives the crew a push target
while keeping the reachable surface to hosts that do not accept arbitrary
content.

**If real GitHub access is genuinely required**, in order:

1. Mirror out from the host, from branches the crew pushed to Gitea. The agents
   never reach the forge at all.
2. If agents must push directly: a fine-grained token scoped to a single
   repository, held host-side via a dynamic source, never a general
   `gh auth token` with account-wide reach.
3. Secret scanning as a pre-receive hook *before* the first agent run, not
   after. It catches the accidental class reliably and the deliberate class not
   at all — which is the right trade, because accidental is the threat model.
4. Allowlist the specific host, and re-run the control-host checks afterwards.

**And reconsider the credential.** Much of the risk above exists because the
token sits in the VM. If the substitution route (Option A) becomes available
again, opening GitHub is a much smaller decision. Under Option B, treat the two
as coupled: the day GitHub is allowlisted is the day the credential's location
starts to matter.

### Honest limits

- Revocation of the model credential is manual and browser-only. Incident
  response can contain the sandbox but cannot script invalidation at the
  provider.
- Credential expiry inside the sandbox presents as no progress, not as an
  error. Indistinguishable from a stalled agent without an explicit check.
- An egress allowlist is a guardrail, not a guarantee — allowlisted hosts
  (GitHub, npm) are themselves exfiltration channels.
- On macOS, Docker already runs inside a VM, so the outer boundary is a
  hypervisor. Escape lands an attacker in a disposable Linux VM, not on the
  laptop. This is more isolation than a Linux host gives by default.

### When to split into multiple sandboxes

Only two cases:

1. An agent must execute genuinely untrusted third-party code.
2. Daemon-level concurrency is needed that namespaces cannot provide.

Not by default.

---

## Layer 2 — Workspace separation (interference)

Inside the single sandbox, agents get separate workspaces so they don't trip
over each other. Cheap, and no security claim attached.

- **Git**: one worktree or branch per agent.
- **Compose**: distinct project names (`-p backend`, `-p frontend`).
- **Kubernetes**: one namespace per agent.
- **Ports**: an allocated range per agent, no overlap.

### Shared infrastructure lives once

Because everyone is on one daemon, cross-agent networking is service-name
resolution rather than published-port choreography.

- k3d / kind cluster — one, shared.
- Gitea — so Argo CD has a git remote to reconcile from without handing an
  agent GitHub push credentials.
- Pull-through registry cache — separate daemons would mean N pulls of the same
  base image.

### Resource budget (Apple Silicon, 36 GB)

Nesting is three deep: Docker Desktop VM → sandbox daemon → k3d node containers
→ pods. Give the VM 20 GB+. A k3d cluster plus Argo CD plus a JVM will not fit
in the 8 GB default. Storage-driver nesting is where the performance cost
lands.

Also: base images must be `arm64` native. Emulated amd64 under a JVM workload
is painful.

---

## Layer 3 — Contract (correctness)

**This is the layer that actually prevents the multi-agent failure mode.**
Three agents in separate workspaces cannot see each other's work. Without an
explicit contract, the frontend agent invents an API the backend didn't build
and *both report success*.

### The contract is an artifact, not an understanding

- **OpenAPI spec written first**, before any implementation. By the supervisor
  or by hand.
- **Generate** the server interface and the typed client from it. The frontend
  then physically cannot call an endpoint that doesn't exist — the generated
  client has no such method. Incompatibility becomes a compile error.
- **Contract tests** (Spring Cloud Contract, Pact) derived from the same spec,
  so drift fails CI rather than surfacing in a demo.

### CI is the only authority on "does it work"

Compile → unit tests → contract tests → schema validation. Runs inside the
sandbox. Deterministic, and it does not care how confident an agent was.

**No agent, including the supervisor, may override CI.**

---

## Layer 4 — Supervisor (planning)

### What it does

- Decomposes the goal into subtasks.
- Writes the initial contract.
- Sequences work: infra → backend → frontend.
- Notices an agent looping, stalled, or drifting off-task.
- Re-plans when a subtask turns out underspecified.
- Adjudicates when the *spec itself* is wrong — the one case CI can't catch,
  because CI validates against the spec.

### What it must not do

- **Verify correctness.** It reads CI output as fact. It does not form its own
  opinion about whether code compiles or an endpoint matches.
- **Enforce policy.** "No pushes to main", "agent B may not touch infra
  manifests", "resource quota per namespace" are policy rules. A policy engine
  enforces them reliably; an LLM asked to enforce them is a policy engine with a
  persuadability bug — and prompt injection is precisely an attack on
  persuadability.

### Why it can't verify even if we wanted it to

Three agents produce thousands of lines. The supervisor's context can't hold
them, so it receives *summaries* — "I implemented the orders endpoint per
spec." It vets a description of an action, not the action. Make it read every
artifact and it's doing the work itself, and the decomposition is gone.

Runtime veto on every action also serialises what the workspaces parallelised:
three concurrent agents become one pipeline with an LLM round-trip between
steps.

### Precedent

Google DeepMind's Co-Scientist (Nature, July 2026) is built this way — a
Supervisor agent orchestrating specialists, with quality signal coming from
separate ranking and validation stages rather than the supervisor's own
judgment.

---

## Threat model

The risk is **not** that the model turns malicious. It's the confused deputy:
the agent is helpful, and the input steering it is attacker-influenced.

- Log lines, issue bodies, README content, dependency metadata, fetched web
  pages — all untrusted text that can carry instructions.
- Directly relevant to the alert-investigation work: alert payloads are the
  least trustworthy text in any production system.
- Concrete failure modes: destructive command against the wrong path;
  `git reset --hard` over uncommitted work; a migration against prod because
  the prod URL was in the environment.

This is why credentials stay outside the sandbox rather than being denied by
configuration inside it. Deny rules are a secondary safeguard, not the
mechanism.

---

## Open questions

- [ ] Pin container image tags used by integration tests. A migration whose
      purpose is proving equivalence between two builds cannot rely on a
      floating tag (`mysql:latest`) — the baseline and the new build could
      resolve different versions on different days, and the parity evidence
      silently stops meaning anything. Pin before recording any baseline.
- [ ] Docker Hub is the first allowlist entry that *accepts* content as well as
      serving it. It requires credentials the sandbox does not have, so the
      practical risk is near zero — but the read-only property of the allowlist
      no longer holds by construction, only by absence of credentials.

- [ ] Does the supervisor run inside the sandbox or outside it? Inside is
      simpler; outside means it survives a sandbox reset and can restart a crew.
- [ ] What does an agent do when it believes the contract is wrong? Needs an
      explicit escalation path, or it will silently work around the spec.
- [ ] How is the contract versioned mid-run? Changing it invalidates work
      already done.
- [ ] Where does human approval sit? Probably: at contract sign-off and at
      merge, not per action.
- [ ] How does the supervisor distinguish credential expiry from an agent
      stalling? Both present as "no progress", but one needs re-auth and the
      other needs re-planning. Expiry warnings do not block requests, so a run
      can strand mid-flight with no error. Probably a pre-run credential check
      rather than a judgment call at runtime — which makes it a deterministic
      check, not a supervisor responsibility.
- [ ] Cost ceiling per run. Three agents looping on a failing test is an
      expensive way to discover a bad spec.
- [ ] Do we need a shared scratch space for artifacts agents hand to each
      other, or is git sufficient?

---

## Bring-up runbook

The sequence that produces a working sandbox, in the order that avoids rework.
Every step that changes sandbox configuration requires a **recreate** — policy
rules, environment variables and workspace mounts all apply at create time, not
to a running sandbox. This is the single most expensive thing to learn late.

1. **Credential.** Read the host client's short-lived access token and pass it
   at create time. Verify with a trivial prompt before anything else.
2. **Egress baseline.** Default-deny. Confirm a control host is refused.
3. **Workspace.** Clone mode gives the sandbox its own copy of the repository —
   the host tree is unreachable, and the sandbox sees *committed state only*.
   Anything uncommitted is invisible to the agent.
4. **Scaffolding, committed.** Agent instructions, hooks, task list and loop
   script live in the repo, because the clone is the delivery mechanism.
5. **Verify the guard hook empirically.** Log the hook payload once to confirm
   field names and path format, then remove the logging. Test the block branch
   by invoking the script directly — asking the agent to violate a rule tests
   its compliance, not the hook.
6. **Discover the egress list by denial, not by guessing.** Run the real build,
   read the policy log, allow what actually denied. Every addition costs a
   recreate, so batch them.
7. **Vendor what redirects.** An allowlist entry covers a hostname, not a
   download. A redirect to an unlisted host reports its error against the
   *original* URL, which is actively misleading. Where the chain passes through
   a host you will not open, vendor the artifact locally instead.
8. **Check the inherited environment before designing around it.** The agent
   kit decides the base image — JDK version, installed tooling — and its
   choices are invisible until something fails.

### Delivering large or binary assets to the sandbox

Clone mode delivers the repository, and only the repository. Three routes for
anything else, with the outcome of each:

| Route | Works in sandbox | Pushable to a forge |
|---|---|---|
| Commit the file plainly | yes | **no** — forge file-size limits reject the push |
| Git LFS | **no** — the clone resolves to a pointer, not the file | yes |
| Read-only workspace mount | yes | yes (file is outside the repo) |

The mount is the only option that satisfies both, and it is a positional
argument at create time: `sbx create <agent> . /path/to/assets:ro`. The mounted
path mirrors the host path inside the VM, so an absolute path in a config file
resolves identically on both sides — which makes `distributionUrl`,
`settings.xml` and similar host-path references portable without rewriting.

This also generalises: the same mechanism carries a warmed dependency cache
(`~/.m2`, `~/.gradle`), which removes artifact egress from the picture
entirely. That matters beyond convenience — two builds resolving independently
from the network can pick up different transitive versions on different days,
and a dependency-parity claim between them is then comparing moving targets.

### Traps, each of which cost a cycle

- **Policy changes need a recreate.** `policy check` reports current global
  policy; a running sandbox keeps what it was created with. The two disagree
  silently.
- **Teardown discards sandbox state.** Commits made inside are reachable from
  the host via the sandbox git remote, but only until the sandbox is removed.
  Fetch before recreating, or accept the rework.
- **Redirects hide the real host.** Gradle's distribution URL 307s to a git
  forge; the 403 is reported against the distribution host. Only the policy log
  shows the truth.
- **Command-sourced secrets pass stdout verbatim**, so a trailing newline lands
  inside the header and produces a clean 401 with a correct-looking config.
- **The agent's self-reports about its own environment are unreliable.** Three
  separate occasions in this project: a claim that credentials are never
  environment variables, a claim that nothing had changed when the listing
  showed otherwise, and a confident account of its own auth path. Check from
  the host with `exec`, not by asking.
- **A completion-signal grep matches the agent's prose about the signal.**
  An agent explaining *why it is not* emitting the completion token contains
  the token. Require a whole-line match near the end of the log
  (`tail -5 | grep -qx`), not a substring match anywhere in it.
- **Git LFS and clone mode are incompatible.** The clone does not resolve LFS
  pointers, so the agent receives a 134-byte text file where a binary should
  be. The failure surfaces later, as a confusing tool error.
- **Rewriting history orphans the sandbox's commits.** They descend from
  history that no longer exists on the host, so a fetch will not merge. Extract
  files instead, or accept the loss.
- **A shell glob or variable in `sbx exec` expands on the host.** Anything the
  host shell would interpret — globs, `$VAR`, `&&`, pipes — must be wrapped in
  `sh -c '...'` or it happens on the wrong side of the boundary, silently
  producing a meaningless result.
- **Decompose so each item's acceptance test is reachable from that item's own
  changes.** A task list that splits "write the build file" from "add the
  dependencies" deadlocks: the first item's test cannot pass without the
  second's work, and a well-behaved agent that respects the ordering stops.
  The failure is in the plan, not the agent — and it is exactly the
  "re-plan when a subtask turns out underspecified" case the supervisor
  exists for.
- **A credential can be revoked, not merely expire.** Signing in to the client
  elsewhere appears to invalidate an existing token. Under Option B this ends
  a running session mid-task and costs a rebuild.

## Validated so far

Tested on macOS, single sandbox, subscription auth. Recorded here so the
decisions above read as measured rather than assumed.

- Private daemon and disposability: not yet exercised end to end.
- Deny-all egress plus a single allowed host: agent starts, authenticates,
  responds. Control hosts refused.
- Proxy-held OAuth via the built-in `anthropic` service: blocked by header
  mismatch. Four header combinations tested against the live endpoint.
- Proxy-held OAuth via a custom secret (placeholder substitution): **worked on
  sbx 0.42.1, blocked on 0.43.0.** Placeholder and inference both confirmed on
  the older version; on 0.43.0 the same configuration 401s silently on a
  freshly created sandbox.
- Command-sourced custom secret with a pinned placeholder: **worked on 0.42.1.**
  The runtime stored no credential at all, only the command.
- Environment-variable credential: works on both versions. Real token inside the
  VM.
- Kit-supplied network allow rules exist, are non-editable, and are reinstated
  at every sandbox create.
- **Clone mode**: the sandbox receives a clone of the host repository at
  `HEAD` — committed state only, mirrored at the same absolute path.
  Uncommitted work is invisible to the agent. The agent's commits return via a
  `git://127.0.0.1:<port>` daemon exposed as the `sandbox-<name>` remote; the
  port is reassigned on every create.
- **Read-only workspace mounts** work locally and are the correct delivery
  route for large binaries and warmed caches. (`-v/--volume` is cloud-only.)
- **The agent kit sets the base image**, including the JDK. Inherited, not
  configured, and invisible until a build fails on it.
- **A Ralph-style loop driven from the host works.** Fresh context per
  iteration, state carried in git plus a journal and done-markers. Seven tasks
  of a real Maven-to-Gradle migration completed across several runs, with
  parity evidence recorded per task and three genuine ambiguities escalated to
  a human rather than guessed.
- **Write guards hold under `--dangerously-skip-permissions`.** A `PreToolUse`
  hook fires, receives an absolute `file_path`, and blocks on exit code 2 with
  its stderr returned to the agent as context. The `Bash` tool bypasses it —
  a hook matched on edit tools does not see `sed -i`.
- **Private Docker daemon: confirmed.** `docker run` inside the sandbox reaches
  a daemon and fails only on egress policy, not on a missing socket.
- **Claude Code does not propagate `CLAUDE_CODE_OAUTH_TOKEN` to child
  processes.** The agent authenticates, but anything it shells out to sees the
  variable unset. This materially narrows the confused-deputy exposure under
  Option B: a credential in the VM environment is not a credential the agent
  can hand to arbitrary code it runs.
- Access-token lifetime measured at ~24h, renewed at expiry rather than ahead
  of it.
- Short-lived access token snapshotted directly into the sandbox environment:
  also works, but superseded by the above.
- Long-lived minted token: works, then revoked; revocation confirmed immediate.
- Raw API calls carrying an OAuth credential are throttled independently of
  subscription quota (429 at 3% session usage), while the same credential used
  by the normal client inside the sandbox is not. The limit tracks the client,
  not the workload — so this says nothing about whether agentic use is
  permitted, and the earlier inference that it did was not supported.

Still open: whether an unattended crew on subscription auth behaves the same as
a single interactive session. Nothing tested so far distinguishes them.

## What to build first

Smallest thing that exercises all four layers:

1. Sandbox definition with allowlist and no credential mounts.
2. One shared compose stack: Gitea, registry cache.
3. A trivial contract — one endpoint, OpenAPI spec, generated client.
4. Two agents: backend and frontend, separate worktrees.
5. CI that fails loudly on contract drift.

If that runs end to end and the drift check actually catches a deliberate
mismatch, the architecture is sound and the rest is scale.
