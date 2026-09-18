# Agent operating rules

This repository is a clone inside an isolated sandbox. Nothing here reaches the
host. Work freely within these rules.

All commands below are run from the repository root.

## Goal

Migrate the build of `backend/` from Maven to Gradle. The Maven build is the
reference implementation. The migration is complete only when the Gradle build
is demonstrably equivalent to it.

## The baseline is immutable

Before starting any task, confirm the Maven build still works:

    cd backend && ./mvnw clean compile

If this fails, stop immediately and write the failure to `state/BLOCKED.md`.
A broken baseline means there is no oracle to migrate against, and any Gradle
work done from that point is unverifiable. Do not attempt to repair the Maven
build in order to proceed — report it and stop.

Re-run this check after every change, not only at the start. The Maven build
must still pass when the session ends.

`backend/pom.xml`, `backend/mvnw` and `backend/.mvn/` are read-only. They are
the oracle the Gradle build is checked against, and they must keep working
until the migration is signed off by a human. Attempts to edit them are
blocked — deliberately.

## Equivalence, not "it builds"

A green Gradle build proves nothing on its own. Before marking any item done:

- **Dependency parity.** The Gradle resolved compile and runtime classpaths
  must match Maven's. Record both under `state/evidence/` and diff them.
- **Test parity.** The same tests must run, and the count must match. Fewer
  tests passing is a regression, not progress.
- **Artifact parity.** The produced jar's contents and manifest must match
  Maven's, allowing for timestamps and build metadata.

Never delete, disable, skip or `@Ignore` a test to make a build pass. Never
narrow a dependency scope to resolve a conflict. If the Gradle build cannot be
made equivalent, write the reason to `state/BLOCKED.md` and stop.

## Write restrictions

`.claude/`, `CLAUDE.md`, `PROMPT.md`, `ralph.sh`, `state/TODO.md` and the Maven
baseline files are read-only. This is deliberate, not a bug.
`state/journal.md`, `state/evidence/` and `state/BLOCKED.md` are yours to write.

## Network

Egress is restricted to an allowlist. A blocked request is policy, not a
misconfiguration to route around. If a build needs a host that is denied, write
it to `state/BLOCKED.md` and stop — do not attempt to change the policy, and do
not vendor or inline a dependency to work around it.

## Commands

- Maven baseline:    `cd backend && ./mvnw clean compile`
- Maven full verify: `cd backend && ./mvnw verify`
- Maven deps:        `cd backend && ./mvnw dependency:list`
- Gradle structure:  `cd backend && ./gradlew projects`
- Gradle build:      `cd backend && ./gradlew build`
- Gradle deps:       `cd backend && ./gradlew dependencies`
