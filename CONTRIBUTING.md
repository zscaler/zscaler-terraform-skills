# Contributing

Thanks for considering a contribution.

## What goes in this repo

This repo contains **agent skills for users of the Zscaler Terraform providers**. It does not contain provider code, and it does not document provider internals.

If your contribution is about how a Zscaler provider is **implemented** in Go (schema design, CRUD functions, acceptance tests, sweepers, release process), it does not belong here — file it against the relevant provider repo at <https://github.com/zscaler>.

If your contribution is about how a Zscaler provider is **used** in HCL (which resources to combine, what arguments mean, how to debug drift, how policy rules compose), it belongs here. Ground every new resource example in the official Terraform Registry page (`https://registry.terraform.io/providers/zscaler/<product>/latest/docs/...`) — never invent attributes from another provider's schema.

## Authoring rules

Read [CLAUDE.md](CLAUDE.md) before writing content. The "Authoring rules — LLM consumption" section is the entire style guide. Reviewers will reject PRs that violate it.

## Workflow

1. Pick the affected skill folder (`skills/zpa/`, `skills/zia/`, `skills/ztc/`, `skills/zcc/`).
2. Edit `SKILL.md` (router) or a `references/*.md` (depth).
3. Bump `metadata.version` in the affected `SKILL.md` and in `.claude-plugin/marketplace.json` (root + plugin entry).
4. Run the local validation commands listed in `CLAUDE.md`.
5. If you changed observable behaviour for an existing scenario, update `tests/baseline-scenarios.md`.
6. Open a PR.

## Source of truth

Every claim about a Zscaler provider attribute, default, or quirk must trace back to one of:

- The provider's `docs/resources/<name>.md` or `docs/data-sources/<name>.md`
- The provider's `examples/<resource_name>/*.tf`
- The provider's `CHANGELOG.md`
- The provider's `.cursor/rules/troubleshoot-*-provider.md`

If you can't trace it, do not write it.
