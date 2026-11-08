# Contributing

Thanks for taking an interest. This project turns a **OnePlus 5T** (`dumpling`) into a small,
always-on Linux server running **postmarketOS**, hardened, with Docker, a Cloudflare Tunnel and
`git push` → auto-deploy. It's a best-effort hobby/test platform, not a commercial product — but
clean, reproducible contributions are very welcome.

## Ways to help

- **Fixes & clarifications** to the guides in [`docs/`](docs/) — if a step didn't work on your setup,
  the fix is valuable (say which pmOS release and host OS you were on).
- **Ports to other phones.** Almost everything here is generic Alpine/OpenRC + Docker; the
  device-specific parts are the flashing scripts and a few kernel workarounds (cgroup v1, host
  networking, nftables). If you got it working on another `pmaports` device, a short notes file or a
  parameterized script is a great PR.
- **Hardening & reliability** improvements (within the constraints below).
- **New app recipes** for the [`pipeline/`](pipeline/) pattern (WordPress, a static site, etc.).

## Ground rules

1. **Free and self-hostable only.** No paid infra, no SaaS lock-in. The whole point is that it runs on
   a dead phone and free tiers. If a change needs a paid service, make it optional and document the
   free path too.
2. **Keep secrets out of git.** Credentials, PATs, tunnel creds and `.env` files live on the device
   under `/srv/nono/secrets/` and are mounted at runtime — never commit them, never bake them into an
   image. See [`.gitignore`](.gitignore).
3. **Respect the archived-kernel constraints.** This port is unmaintained: no docker bridge
   (host networking only), cgroup **v1**, `nftables` (not the iptables shim), no `/dev/net/tun`. Don't
   submit changes that assume a normal kernel without saying so.
4. **No lockout footguns.** The phone is headless with no keyboard. Any change touching SSH or the
   firewall must keep the self-revert safety pattern documented in
   [`docs/guides/4-hardening.md`](docs/guides/4-hardening.md).
5. **Test on real hardware** where you can, and say what you tested on. "Untested, but should work" is
   fine as long as you label it.

## Workflow

1. **Open an issue first** for anything non-trivial (a new device port, a feature, a behavior change),
   so we can agree on the approach before you spend time. Small fixes and typo PRs can skip this.
2. **Fork** the repo and create a topic branch off `main`. Name it `type/short-description`, e.g.
   `feat/pinephone-port`, `fix/cloudflared-logpath`, `docs/hardening-typo`.
3. Make focused commits (see **Commit messages** below). **One logical change per PR** — don't mix a
   refactor, a feature and a reformat.
4. Open a **pull request against `main`** with a clear **what** and **why**, and link the issue it
   closes (`Closes #123`). Fill in the PR template.
5. A maintainer reviews; address feedback by pushing more commits (we squash on merge, so you don't
   need to rewrite history during review).

## Commit messages — Conventional Commits

This repo follows [**Conventional Commits**](https://www.conventionalcommits.org/). The subject line is:

```
<type>(<scope>): <imperative summary>
```

- **types:** `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`
- **scopes** (optional but encouraged): `phone`, `pipeline`, `wsl`, `windows`, `docs`, `runner`,
  `cloudflared`, `console`
- **summary:** imperative mood, lower-case, no trailing period, aim for ≤ 72 chars
  ("add", not "added"/"adds").
- **breaking changes:** add `!` after the type/scope (`feat(pipeline)!: ...`) **and** a
  `BREAKING CHANGE:` footer explaining the migration.
- Put the *why* in the body when it isn't obvious; wrap the body at ~72 columns.

Examples (the style already used in this repo's history):

```
feat(phone): power button hold = clean shutdown
fix(cloudflared): log under the user's home so the service child survives
docs(guides): split the flashing walkthrough out of the README
```

## Code & docs style

- Keep scripts **POSIX-ish** where the target is Alpine's `sh`/busybox (the phone), and note when a
  script intentionally needs `bash` (e.g. `pipeline/deploy.sh`).
- Run shell scripts through **`shellcheck`** before pushing.
- Match the existing doc style: short, precise, with the **why** behind each non-obvious step (this
  repo is as much a field guide as it is scripts).
- Never commit secrets, PATs, tunnel creds or `.env` files — they live on the device under
  `/srv/nono/secrets/` and are mounted at runtime. See [`.gitignore`](.gitignore).

## Reporting problems

Use the **[issue tracker](../../issues)** — there are templates for **bug reports**, **device ports**
(getting it running on another phone), and **feature requests**. For a bug, include: the phone model,
the **postmarketOS release** (`cat /etc/os-release`), your host OS (Windows + WSL2 version, or native
Linux), the exact command, and the full error. The
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) file is where hard-won fixes accumulate — if you
solved something that isn't there, add it in your PR.

## Be decent

Be respectful and assume good faith. This is a hobby project people contribute to in their spare time;
keep discussion constructive and on-topic.

## License

By contributing you agree your contributions are licensed under the [MIT License](LICENSE) that covers
this project.
