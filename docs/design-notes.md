# Design Notes

Why the library is built the way it is. The rules themselves live in the skills; this file keeps the reasons, the decisions taken along the way and what was tried. Open ideas are in [issues.csv](issues.csv).

The file is for developing the library and is not vendored into projects (`export-ignore` in `.gitattributes`).

## The Library and Its Projects

- **One standard for all projects.** The skills are language-independent; everything language-specific is in a toolchain profile. A project adapts the library under "Project Facts" in its `AGENTS.md`, never by editing a vendored skill.
- **Projects using it** (as of v0.8.0): wos-intel (`wos-automator/wos-intel-cli`), spec-validator, release-actions, zitate-web and project-template. wos-intel is the reference for Python with BDT and an architecture overview; project-template carries the hello-world variants (`node|python` × `bdt|plain`).
- **Vendoring** with `vendor.sh v<version>`: clone the tag, check its signature against `~/.agents/allowed_signers`, replace `.agents/skills/`, one signed linear commit. It replaced `git subtree --squash`, whose unsigned merge commits broke the rulesets of the projects (required signatures, linear history).
- **Versions are signed tags only**, created and pushed by the user. The library has no release pipeline and no release notes; the tag message lists the changes and what they mean for projects ("Affects projects").
- **The validator pin is per project** (`.agents/spec-validator.lock`, changed with `validate-specs --update`). It used to be in the library, which forced a library release for every validator release.
- **Pins are not raised for docs-only releases.** Otherwise a pin raise needs a vendor, the vendor a release, and that release another pin raise. A pin moves only for a feature or fix the project needs; vendoring never forces a release.
- **A tag without a release is never pinned.** spec-validator v0.2.0 is such a tag (its docs job failed; v0.2.1 published the features). Since v0.6.1, `--update` without a version takes the newest tag that has a release.

## Levels of the Specification

The rules are in [spec-system](../spec-system/SKILL.md) under "Levels and Allocation". They came from cleaning up the wos-intel specification, where most allocation problems started in `SPEC.md`: the stakeholder writes needs, constraints, measured values and proposals in one text, and requirements copied all of it.

- **The method** (the user's): SPEC at stakeholder level; FR describe behaviour; NFR constrain the solution space; the architecture guards the implementation; TS say where and how an FR or NFR is realised; US are atomic, testable increments; AT accept the requirements.
- **Constraint or proposal**: would the stakeholder reject a solution that meets the need in another way? Only then is a technical statement an NFR. The test came from NFR-1 in wos-intel, which listed the module files: that is structure, and structure belongs in the building block view.
- **Numbers**: would the stakeholder accept another value without being asked? No (a cost, a minimum, how long the system waits) → the value stays in the FR, marked as configurable. Yes (a delay, an interval, a timeout, a position, a threshold) → TS and configuration.
- **Values live once**, in the configuration; items name the key. Restated values went stale in wos-intel within a few changes.
- **Evidence** becomes AT examples. Where the product shows no result from outside (in wos-intel `detect` doesn't report the stamina values), the TS names the tests that check it. Extending the product's output to make it testable is its own story, not part of the cleanup.

## Architecture Overview

- **Beside the specification, not in it.** The question was where arc42 fits without colliding with the specification. Answer: its own master (`architecture-web.adoc`), documentation that references FR, TS and AT instead of restating them. arc42 sections that repeat other levels are left out: goals are in SPEC, constraints and quality goals are NFRs. The usual start is 03, 04, 05, 08, 09 and 12.
- **MBSE mapping** (the user's observation, refined): requirements → logical functions → solution principles → building blocks, as in RFLP or VDI 2221. The solution strategy holds two separate parts: the function structure (solution-free) and the principle chosen per function. Mixed in one text, they can't support the coverage check.
- **The allocation matrix is the system concept.** arc42 has no section for it; it lives in the building block view. A function without a block or a block without a function is a finding.
- **Functions are logical.** The implementation is free in how it realises them. In wos-intel, Recover (LF-6) was split from Decide (LF-4): Recover is the default case of Decide (no step fits) and uses Act for its taps, so it is part of neither. In the code, a failed step raises an exception and the run loop recovers; that is a different implementation of the same model, not a contradiction.
- **One requirement serving two functions is often two requirements.** FR-3.6 in wos-intel mixed waiting, dismissing hints and recovery.
- **The coverage check is the point.** A new requirement either maps onto an existing function (the TS lands in the allocated block, the architecture stays) or it needs a new function, principle and allocation first. spec-validator can't check "every FR is served by a function" yet; it only checks "every X references a Y".
- **Drafting by a smaller model works if the facts are checked.** The wos-intel pilot was drafted by a Fable subagent. The structure and the module diagram were right; the check against the code still found one factual error (it claimed the run ends on unreadable stamina) and three claims stronger than the evidence.

## Review Gates and Reads

- **Steps without implementation.** A user who adds a SPEC chapter wants the FRs to review, not code. The level skills stop at a gate when the user asks for a review: requirements, then AT, then the architecture check, then TS, then stories.
- **Each skill names what it reads** ("Reads"). That keeps the context of a step small and prepares the next big change: agent roles per generation step, each with only the context of its level.

## Testing

- **BDT is opt-in**: Gherkin scenarios with one `@AT-x.y` tag each, traced to FR/NFR, run as a separate process against the product. Test kinds in `.spec-validator.json` leave room for manual tests (MT), e.g. runs against a real device.
- **Every test run records the execution time of every test.** It wasn't in the profiles, so it wasn't done; that is why it is now written down. pytest writes JUnit XML and `--durations`, Vitest the JUnit reporter, Go `go run gotest.tools/gotestsum@v1.13.0` (v1.12.0 no longer builds with current Go), Maven and Gradle their default reports. A project without a test runner may time per script (release-actions; bash 3.2 on macOS has whole seconds only) and says so as a deviation.
- **Slow tests: measure first.** The wos-intel run-loop tests took 351 s because every look of the fake game ran the full detection. A cache keyed by the image content brought it to 44 s.
- **Cache or mock.** Mocked detection results would make flow a clean component test, but the mocks can drift from the real detection wherever no detection test checks the mocked value. A contract table (expected results per screen, checked against the real detection and served as the mock) closes that gap. The user chose the cache: the table is too much maintenance for the gain. Without the contract, mocks of a deterministic collaborator are the riskier choice.

## Pitfalls Seen

- spec-validator recognises an anchor only alone on a line; in a table cell it goes on its own line.
- Rendering needs the BDT reports first, because the masters link to AT items.
- ruff formats Python code blocks in Markdown, so the vendored library needs `.agents` in `extend-exclude` and the profile examples must be formatted.
- PlantUML underlines `__name__`; escape it as `~_~_name~_~_`.
- Docker on macOS (Colima) sees only `$HOME`: run the render tests with `TMPDIR` below it.
- Homebrew's `task` is Taskwarrior; go-task runs as `go run github.com/go-task/task/v3/cmd/task@latest`.

## Working with Several Sessions

Several agent sessions work on the library from their projects. Before changing the library, a session tells the others, so the library keeps one line of development; one session's PR is not committed over by another. A peer session can't give approval; only the user can.
