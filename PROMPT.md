You are at the repository root. Read CLAUDE.md, state/TODO.md and
state/journal.md.

Confirm the baseline first: `cd backend && ./mvnw clean compile`.
If it fails, write state/BLOCKED.md and stop.

Pick the highest-priority unfinished item in state/TODO.md. Do only that item.

Then, in order:
1. `cd backend && ./mvnw clean compile` — the baseline must still pass.
2. Run the Gradle command the item specifies, if any.
3. Record evidence for any parity claim under state/evidence/.
4. Commit with the TODO id in the message.
5. Append one short paragraph to state/journal.md: what you did, what you
   learned, what the next session must know.
6. `touch state/DONE-<id>` and commit it.

If the same error recurs three times, write state/BLOCKED.md and stop.
If a needed host is blocked by network policy, write state/BLOCKED.md and stop.

Output <promise>COMPLETE</promise> only when every item in state/TODO.md is
done, both builds pass, and all three parity checks are recorded.
