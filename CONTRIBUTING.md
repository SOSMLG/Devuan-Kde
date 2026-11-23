# Contributing

Small changes, small pull requests.

1. Branch from `main`.
2. Make one complete change.
3. Use a Conventional Commit style title: `feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `security:`.
4. Run `./install.sh --verify` before opening a pull request.
5. Let the read-only CI checks pass, then squash-merge.

No tests. Validation means parsers, syntax checks and the read-only verifier above.

No secrets in the tree. Never rewrite pushed history; use `git revert`.

Guides: [English](https://github.com/SOSMLG/.github/blob/main/docs/GIT_GUIDE.md) / [Arabic](https://github.com/SOSMLG/.github/blob/main/docs/GIT_GUIDE.ar.md).
