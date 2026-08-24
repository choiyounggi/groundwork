# Issue #6 verification — google/skills marketplace layout proposal

Source: [groundwork#6](https://github.com/choiyounggi/groundwork/issues/6) — "proposal:
borrow google/skills marketplace layout — submodule-sourced plugin entries +
multi-harness manifests". The issue itself flags its evidence as `[추정]`
(structural observation only, not verified against a real install). This report
verifies each of the 3 candidates the issue implies against official docs and/or
real measurement, and records what was actually done.

## Candidate 1 — ref pin on the dev-loop marketplace entry

**Verdict: PASS — adopted.**

The dev-loop plugin entry in `.claude-plugin/marketplace.json` used a `url`-type
source with no `ref`, so installs track the repository's default branch HEAD
rather than a fixed release.

Evidence (official docs, `code.claude.com/docs/en/plugin-marketplaces`, fetched
2026-08-24):

> | Source | Type | Fields | Notes |
> | `github` | object | `repo`, `ref?`, `sha?` | |
> | `url` | object | `url`, `ref?`, `sha?` | Git URL source |
>
> "Git-based plugin sources support both `ref` (branch/tag) and `sha` (exact
> commit)."

and the documented example for a `url`-type source:

```json
{
  "name": "git-plugin",
  "source": {
    "source": "url",
    "url": "https://gitlab.com/team/plugin.git",
    "ref": "main",
    "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
  }
}
```

`ref` is an optional field on the same `url` source type dev-loop's entry already
uses — no source-type migration needed.

The docs also document a plugin-entry-level `version` field, independent of the
source:

> "`version` (string): Plugin version. If set (here or in `plugin.json`), the
> plugin is pinned to this string and users only receive updates when it
> changes."

This is the same field guardrails (`"version": "1.2.1"`) and memory-loop
(`"version": "1.5.0"`) already carry — adding it to dev-loop is consistent with
the marketplace's existing convention, not a new pattern.

Real measurement — dev-loop's actual latest release tag (read-only, no install
side effects):

```
$ git ls-remote --tags https://github.com/choiyounggi/dev-loop.git
...
9fd5c4b96ce840484f8830800c5e38882619e5bc	refs/tags/v1.9.0
```

`v1.9.0` is the highest (and most recent) tag.

**Implemented**: `.claude-plugin/marketplace.json` dev-loop entry now has
`"source": {"source": "url", "url": "...", "ref": "v1.9.0"}` and
`"version": "1.9.0"`.

**Limitation**: did not run `/plugin marketplace add` / `/plugin install` against
this change — that has a real side effect (fetches and installs the pinned ref)
and is out of scope for a read-only verification pass. The pin's syntax is
verified against the documented schema and example above, not against a live
install.

## Candidate 2 — git submodule + submodule-sourced marketplace entry

**Verdict: FAIL — rejected.**

The proposal is to register dev-loop (and future third-party plugins) as a git
submodule under `plugins/`, in addition to a `source.ref`-pinned marketplace
entry, mirroring google/skills' `.gitmodules`.

Checked the same official marketplace-schema documentation used for Candidate 1:
the plugin `source` types it defines are `relative path`, `github`, `url`,
`git-subdir`, `npm`, `archive`, `command` — no `submodule` source type, and no
mention of `.gitmodules` anywhere in the doc. A git submodule is an orthogonal
git mechanism (vendors the source into a local subtree for tooling that reads it
off disk); it is not something `marketplace.json`'s installer reads or requires.

Candidate 1 (a `ref`-pinned `url`/`github` source) already gives version-stable,
non-HEAD-tracking installs on its own — a submodule adds a second, redundant
pinning mechanism without a schema hook that consumes it. groundwork's own
architecture (per this task's brief) intentionally does not vendor dev-loop's
source into this repo; it links out to the plugin's own repo. A submodule
would reverse that by checking out a full local copy that plugin installs never
read.

The issue's own evidence for this candidate is `[추정]`: "not verified that
submodule-sourced entries resolve correctly on install." No such verification
was attempted here either, since it would require a real install to observe;
given the schema already shows no submodule-specific source type, that install
would not test anything the docs don't already answer.

**Reconsider if**: a future Claude Code marketplace schema version adds a
submodule-aware source type or documents that `marketplace.json` installers
read `.gitmodules`, *and* there is a concrete need to vendor a plugin's source
locally (e.g. offline installs, air-gapped teams) that a `ref` pin alone doesn't
satisfy.

## Candidate 3 — parallel manifest for other harnesses (`.agents/plugins/marketplace.json`)

**Verdict: FAIL — rejected.**

The proposal is to add a second manifest at `.agents/plugins/marketplace.json`
mirroring `.claude-plugin/marketplace.json`, for Codex/Antigravity/other
harnesses to consume, per google/skills' layout.

Fetched the cited source (`github.com/google/skills`, README `#plugins`
section) directly. It gives separate per-harness install commands:

- Claude Code: `claude plugin marketplace add google/skills`, then
  `claude plugin install <plugin>@google-plugins`
- Codex: `codex plugin marketplace add google/skills`, then install from the
  `/plugins` browser
- Antigravity: `agy plugin install https://github.com/google/skills/<plugin-path>`

None of these instructions, nor any other part of that README, states that the
Codex or Antigravity commands read `.agents/plugins/marketplace.json`
specifically — the README does not name that file at all. Each harness's
install command could be reading its own manifest format from its own
convention, unrelated to the file path the issue assumes.

This is exactly the gap the issue itself flags: `[추정]`, "not verified that the
second manifest is actually consumed by those harnesses." That gap was not
closed by this check — Codex's and Antigravity's own docs (not this repo's
domain, and not fetchable via `docs.anthropic.com`/`code.claude.com`) would be
the actual source of truth, and installing either CLI to test consumption has
side effects out of scope for this task. Per this task's verification
constraint (doc evidence or real measurement required for adoption), the
candidate stays unverified and is rejected rather than assumed safe.

**Reconsider if**: Codex's or Antigravity's own documentation (or a maintainer
of either project) confirms they read a `.agents/plugins/marketplace.json` path
by convention, or groundwork commits to supporting a non-Claude-Code harness as
a first-class target (which is a separate scope decision, not implied by this
issue).

## Summary

| # | Candidate | Verdict | Basis |
|---|-----------|---------|-------|
| 1 | ref pin on dev-loop entry | **Adopted** | `code.claude.com/docs/en/plugin-marketplaces` schema table + example; `git ls-remote --tags` for the actual latest tag (`v1.9.0`) |
| 2 | git submodule + submodule source | Rejected | Same schema doc: no submodule source type exists; ref pin (candidate 1) already covers the version-stability need without it |
| 3 | `.agents/plugins/marketplace.json` for other harnesses | Rejected | google/skills README does not document that any harness reads that path; unverifiable without a side-effecting install of another CLI, out of scope here |

Only candidate 1 required a code change. `.claude-plugin/marketplace.json`'s
dev-loop entry now carries `ref: "v1.9.0"` + `version: "1.9.0"`;
`tests/check-versions.bats` gained a normal + a mismatch-detection case for the
new ref==version invariant (`check-versions.sh` itself is unchanged — it already
skips non-local sources by design, so the new invariant is checked directly in
the bats file). Candidates 2 and 3 are unchanged from the current repo state.
