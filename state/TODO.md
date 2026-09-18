# TODO — Maven to Gradle migration for backend/

Baseline first. Do not start an item until the previous one is committed.

- [ ] T1: Record the Maven baseline. Write `./mvnw dependency:list` output, the
      test count from `./mvnw test`, and `jar tf` of the built artifact into
      state/evidence/maven-*.txt. Commit. No build changes.
- [ ] T2: The Gradle wrapper and backend/settings.gradle.kts are already
      committed. Verify `cd backend && ./gradlew projects` runs and lists the
      expected structure. If pom.xml declares <modules>, add the corresponding
      include() lines and record the mapping in state/journal.md. No build
      logic yet.
- [ ] T3: Create backend/build.gradle.kts with plugins, repositories, and the
      java toolchain version matching pom.xml. `./gradlew compileJava` must
      succeed.
- [ ] T4: Port dependencies with correct scopes (compile/runtime/test/provided
      → implementation/runtimeOnly/testImplementation/compileOnly). Record
      `./gradlew dependencies` into state/evidence/ and diff against T1.
- [ ] T5: Port the test configuration. Test count must equal T1's.
- [ ] T6: Port packaging — manifest, resources, shading if present. Diff
      `jar tf` against T1's.
- [ ] T7: Port remaining plugins (compiler args, resource filtering, profiles).
      List anything with no Gradle equivalent in state/journal.md.
- [ ] T8: Write state/MIGRATION-REPORT.md: parity evidence, behavioural
      differences, and anything a human must decide. Do not remove pom.xml.
