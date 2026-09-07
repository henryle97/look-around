# Distributing LookAround: DMG + Homebrew Cask

One artifact, two channels. Every release publishes a single
`LookAround-<version>.dmg` to a GitHub Release; the Homebrew Cask
downloads that same DMG.

> **Unsigned-app caveat.** LookAround is distributed without an Apple
> Developer certificate (deliberate $0 distribution, no signing ever),
> so it lives in a personal tap (`henryle97/tap`), not the official
> `homebrew/cask` repo — official casks must pass Gatekeeper without
> workarounds.

## Releasing a new version

The git tag is the single source of truth for the version — no manual
plist bump needed:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

The release workflow (`.github/workflows/release.yml`) builds the app,
stamps `CFBundleShortVersionString` from the tag (`package-dmg.sh`
refuses to go backwards if the checked-in plist is already ahead — a
stale-tag guard), packages `dist/LookAround-0.1.0.dmg`, attests its
build provenance, and creates the GitHub Release with the DMG attached.
It also prints the ready-to-paste Cask update in the job summary, and —
if `HOMEBREW_TAP_TOKEN` is configured (below) — pushes it to the tap
repo automatically.

### Releasing from a local machine instead

`./scripts/release-local.sh [--version 1.0.0] [--yes]` builds, packages,
and publishes the same way, without needing a tag push or CI. It's
gated on GitHub **permission**, checked live via `gh api` against
whichever account `gh auth status` is currently logged into — not a
hardcoded username — and refuses to run for anyone without `ADMIN` on
this repo. It prompts for confirmation before publishing (skip with
`--yes`) since a release is public and immediate.

It won't attach a build-provenance attestation (that needs GitHub
Actions' OIDC token, unavailable on a laptop) — use the tag-push path
above when that matters. The two are safe to mix: the CI workflow
checks for an existing release first and skips cleanly if
`release-local.sh` already published that version, so pushing the tag
afterward (e.g. to keep tags and releases in sync) won't double-publish.

## One-time tap setup

```sh
# 1. Create a public GitHub repo named homebrew-tap under your account,
#    then inside it:
mkdir -p Casks
cp /path/to/look-around/packaging/homebrew/Casks/lookaround.rb Casks/
# 2. Fill in version + sha256 for the current release
#    (see "Manual Cask update"), commit, push.
git add Casks/lookaround.rb
git commit -m "Add lookaround cask"
git push -u origin main
```

Users then install with:

```sh
brew install --cask henryle97/tap/lookaround
```

### Optional: automatic tap updates on release

1. Create a fine-grained personal access token with **contents: read
   and write** on the `homebrew-tap` repo only.
2. In this repo: Settings → Secrets and variables → Actions →
   New repository secret → name `HOMEBREW_TAP_TOKEN`, value the token.
3. (Only if your tap repo is named differently) set an Actions
   **variable** `HOMEBREW_TAP_REPO` to e.g. `henryle97/homebrew-tap`.

## Validating the cask

```sh
# In look-around (no published release required):
./scripts/test-cask.sh --version 0.1.0
```

This stamps the template with the real `dist/` DMG's version + sha256
and, inside an ephemeral local tap (removed afterwards), runs `brew
audit` + `brew style`, installs into an isolated `--appdir` (your
`/Applications` is untouched), then `uninstall --zap` and asserts the
settings plist is gone. Existing
`~/Library/Preferences/com.lookaround.app.plist` settings are backed up
and restored; note the running app is quit by bundle id during the
uninstall step, so relaunch it afterwards if you keep it running.

Two warnings are expected before the first release and disappear on
their own: "release asset not reachable" and "homepage not reachable".
Cask defects fail loudly instead.

After the first release is published (asset + Pages live), also run
once against the real tap:

```sh
brew audit --cask henryle97/tap/lookaround
brew livecheck --cask henryle97/tap/lookaround   # should report the release tag
brew install --cask henryle97/tap/lookaround && brew uninstall --cask --zap lookaround
```

(Use default `brew audit`, not `--new`: `--new` additionally demands a
Gatekeeper-passing signature, which an unsigned-forever app never has.)

## Manual Cask update (no automation)

```sh
# In look-around:
./scripts/package-dmg.sh --version 1.0.0
cat dist/LookAround-1.0.0.dmg.sha256

# In your homebrew-tap checkout:
/path/to/look-around/scripts/bump-cask.sh 1.0.0
git diff   # should show only version + sha256 lines
git commit -am "lookaround 1.0.0" && git push
```

Users upgrade with `brew upgrade --cask lookaround`.

## First-launch Gatekeeper note

Homebrew does not make an unsigned app trusted. Tell users that on
first launch macOS may block LookAround, and to approve it via
System Settings → Privacy & Security → Open Anyway (or Finder →
right-click → Open). Do not advise disabling Gatekeeper or stripping
quarantine flags. This note ships in the README, the release notes
(`RELEASE-NOTES.md`), and the website.
