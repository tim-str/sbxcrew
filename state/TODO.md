# TODO — Maven to Gradle migration for backend/

Baseline first. Do not start an item until the previous one is committed.
Each item's acceptance test must be satisfiable by that item's own changes.

- [ ] T1: Record the Maven baseline. Write `./mvnw dependency:list` output, the
      test count from `./mvnw test`, and `jar tf` of the built artifact into
      state/evidence/maven-*.txt. Commit. No build changes.

- [ ] T2: Verify `cd backend && ./gradlew projects` runs and lists the expected
      structure. If pom.xml declares <modules>, add the corresponding include()
      lines and record the mapping in state/journal.md. No build logic yet.

- [ ] T3: Create backend/build.gradle.kts with plugins, repositories, the Java
      toolchain matching pom.xml, and all dependencies ported with correct
      scopes (compile/runtime/test/provided → implementation/runtimeOnly/
      testImplementation/compileOnly). Plugin versions must match the Maven
      equivalents exactly. `./gradlew compileJava` must succeed. Record
      `./gradlew dependencies` into state/evidence/ and diff against T1's
      Maven dependency list. Note any resolved-version differences in
      state/journal.md.

- [ ] T4: Port the test configuration so `./gradlew test` runs. The test count
      must equal T1's. Record the output into state/evidence/.

- [ ] T5: Port packaging. This is a Spring Boot project, so the deliverable is
      an equivalent executable boot jar, not a plain jar — port whatever
      plugin configuration the packaging requires as part of this item rather
      than deferring it. Diff `jar tf` and the manifest against T1's.

- [ ] T6: Port any remaining build configuration not covered above — compiler
      arguments, resource filtering, profiles. List anything with no Gradle
      equivalent in state/journal.md.

- [ ] T7: Write state/MIGRATION-REPORT.md: parity evidence for dependencies,
      tests and artifact; behavioural differences; and anything a human must
      decide. Do not remove pom.xml.
