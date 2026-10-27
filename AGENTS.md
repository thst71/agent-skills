# Developing agent-skills

This repository is the agent-skills library itself. Projects vendor it into `.agents/skills/`; this file, `docs/` and `tests/` stay here (`export-ignore` in `.gitattributes`). What the library is and how projects use it: [README](README.md).

## Before You Start

1. Read [docs/design-notes.md](docs/design-notes.md): why the library is built the way it is, and the decisions taken so far. Don't reopen one of them without a new reason.
2. Read [docs/issues.csv](docs/issues.csv): the open ideas. Work on an idea starts from its row.
3. Before changing the library, tell the other agent sessions working on projects that use it; one line of development, no commits over another session's open PR.

## Rules

- The rules for skills are in the README under "Contributing"; commits follow the [commit](commit/SKILL.md) skill with the skill or profile name as scope (`docs` for this file and `docs/`).
- Changes go through a pull request. CI checks that relative Markdown links resolve, runs shellcheck on the shell scripts, `tests/launcher_test.sh` and `tests/profile_snippets_test.sh` (actionlint on the workflow snippets of the profiles); run the same locally before pushing. On pull requests and on `main`, the workflow `template` also runs every project-template variant with the library of that commit in place of its vendored version.
- Versions are signed tags, created and pushed by the user only. Before a tag, the check run of the commit to tag (on `main`) must pass, the workflow `template` included. Prepare the tag message: the changes, then "Affects projects" (what a project has to do after vendoring).
- A skill never names a project. Examples from a project go into the design notes, not into a skill.

## Keeping the Notes

- **A decision or a lesson** (why something is the way it is, what was tried and dropped) goes into `docs/design-notes.md`, in the section it belongs to. Rules go into the skills; the notes keep only the reason.
- **A new idea or a deferred task** becomes a row in `docs/issues.csv`. A finished idea's row is removed in the change that finishes it.

`docs/issues.csv` is RFC 4180 CSV, UTF-8, one row per future GitHub issue:

| Column | Content |
|---|---|
| `id` | `AS-<n>`, never reused; referenced by `depends_on` |
| `repository` | `owner/repo` the issue belongs to |
| `type` | GitHub issue type: `Feature`, `Task` or `Bug` |
| `title` | the issue title |
| `labels` | separated by `;` |
| `milestone` | empty until the user assigns a version |
| `depends_on` | ids separated by `;` |
| `body` | Markdown: Context, Idea, Open Questions, Done When |

Edit it with a CSV library, not by hand: bodies span several lines and quotes are doubled.
