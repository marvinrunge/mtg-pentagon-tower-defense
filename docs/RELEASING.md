# Releasing a build to a tester

The repo is **private**, so a GitHub Release is the distribution channel and a GitHub
account is the key to it. That is the whole design: no second repo, no upload service, no
secrets to rotate, nothing that can quietly stop working between builds.

## One-time setup

**1. Give the tester read access.**
`Settings → Collaborators → Add people`. Collaborators on a private repo are free and
unlimited, and read access lets them download releases and nothing else.

**2. Have them turn on release notifications.**
On the repo page: `Watch → Custom → ✅ Releases → Apply`.

Plain "Watch" is not enough on its own for what they want, and "All Activity" mails them
every push — Custom → Releases is the setting that mails them exactly once per version.

## Publishing a version

```bash
git tag -a v0.3.0 -m "Skill sounds, boss entrance"
git push origin v0.3.0
```

That is the entire process. The tag triggers the workflow, which builds the `.exe`,
creates the Release, attaches the binary, and writes the changelog from the commits since
the previous tag.

Pushing to `master` also builds — that is what catches a break early — but it does **not**
create a Release and does **not** mail anyone. Only a tag does.

## What the tester receives

An email titled `[marvinrunge/mtg-pentagon-tower-defense] Release v0.3.0`, linking to a
page with the `.exe` and the commit log. The release text tells them to expect
**"Windows protected your PC"** on first run and to click *More info → Run anyway* — an
unsigned build always triggers that, and it looks like a virus warning if nobody said so
first.

## Check this once, on the first release

**Did the mail actually arrive?** The Release is created by the workflow rather than by a
person, and that is the one part of this worth confirming rather than assuming. Ask them
after the first tag.

If it did not arrive, the fallback needs no rebuild: the Release page has a permanent
link, so sending it manually works, and a Discord webhook step can be added to the
workflow later.

## Version numbers

`vMAJOR.MINOR.PATCH`, and the `v` prefix is required — the workflow triggers on `v*` and
attaches to a release only for `refs/tags/v*`. A tag without it builds nothing and
publishes nothing.

Re-tagging the same version does not update an existing release cleanly. Bump the number
instead; they are free.
