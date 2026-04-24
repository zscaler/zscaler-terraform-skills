# Contributing

Thanks for considering a contribution.

## What goes in this repo

This repo contains **agent skills for users of the Zscaler Terraform providers**. It does not contain provider code, and it does not document provider internals.

If your contribution is about how a Zscaler provider is **implemented** in Go (schema design, CRUD functions, acceptance tests, sweepers, release process), it does not belong here — file it against the relevant provider repo at <https://github.com/zscaler>.

If your contribution is about how a Zscaler provider is **used** in HCL (which resources to combine, what arguments mean, how to debug drift, how policy rules compose), it belongs here. Ground every new resource example in the official Terraform Registry page (`https://registry.terraform.io/providers/zscaler/<product>/latest/docs/...`) — never invent attributes from another provider's schema.

## Authoring rules

Read [CLAUDE.md](CLAUDE.md) before writing content. The "Authoring rules — LLM consumption" section is the entire style guide. Reviewers will reject PRs that violate it.

## Workflow

1. Pick the affected skill folder (`skills/zpa-skill/`, `skills/zia-skill/`, `skills/ztc-skill/`, `skills/zcc-skill/`, `skills/best-practices-skill/`).
2. Edit `SKILL.md` (router) or a `references/*.md` (depth).
3. Run `make validate` (and `make spec-check` if `gh ≥ 2.90.0` is installed) — see `CLAUDE.md` for the full validator list.
4. If you changed observable behaviour for an existing scenario, update `tests/baseline-scenarios.md`.
5. Open a PR with a [conventional commit](https://www.conventionalcommits.org/) subject (`feat:` / `fix:` / `docs:` / `chore:`) — semantic-release picks the version bump on merge. **Do not edit version numbers by hand.**

## Source of truth

Every claim about a Zscaler provider attribute, default, or quirk must trace back to one of:

- The provider's `docs/resources/<name>.md` or `docs/data-sources/<name>.md`
- The provider's `examples/<resource_name>/*.tf`
- The provider's `CHANGELOG.md`
- The provider's `.cursor/rules/troubleshoot-*-provider.md`

If you can't trace it, do not write it.
