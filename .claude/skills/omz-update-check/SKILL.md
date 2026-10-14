---
name: omz-update-check
description: Use when Oh My Zsh was updated (omz update, auto-update, "o my zsh се обнови", "omz беше обновен") and the user wants to see what changed, check that the zsh settings kept in ~/bin still work, or "sync" or "keep our setup as before" after the update.
---

# Oh My Zsh post-update check

## Overview

Oh My Zsh lives in `~/.oh-my-zsh` (its own git tree). Our zsh setup lives in
this repo under `settings/osx/home`. After an update there is normally
**nothing to copy**. The job is to prove that the update did not break our
setup, and to list what changed for us.

Our custom plugins (`you-should-use`, `zsh-bat`) load through `ZSH_CUSTOM`,
which `zshrc` points at `settings/osx/home/oh-my-zsh/custom`.
`zsh-autosuggestions` and `zsh-syntax-highlighting` come from OMZ stock.
Never symlink over `~/.oh-my-zsh/custom`: `omz update` then fails to autostash
(see commit `09389ac` and the comment in `create_links`).

## Steps

1. Run the fact collector and read all of its output:
   `bash .claude/skills/omz-update-check/check.sh` (from the repo root).
   It takes the range of the **latest** pull from the OMZ reflog (section 2
   shows earlier pulls too). If an earlier pull was never checked, or the
   reflog has no pull entry, pass the range:
   `bash .claude/skills/omz-update-check/check.sh OLD NEW`.
2. Section 1 must be empty. Local changes or a stash in `~/.oh-my-zsh` mean the
   update hit something local. Stop and report it.
3. Section 3: every plugin must be `custom` or `stock`. `MISSING` means a
   plugin was removed or renamed upstream. Check `git log OLD..NEW -- plugins/<name>`.
4. Sections 4 and 6: read the real diff for every used plugin and every `lib/`
   file that changed (`git -C ~/.oh-my-zsh diff OLD NEW -- <path>`). This
   includes upstream bumps of `zsh-syntax-highlighting` and
   `zsh-autosuggestions`; they are plain files in OMZ git. Check each
   change against our options and files: `zshrc` sets `noclobber`,
   `extendedglob`, `ZSH_THEME=""` and loads `~/.zshprompt` after OMZ; the
   terminal is Ghostty (`TERM=xterm-ghostty`).
5. Section 6 clashes: a hit means a new OMZ alias or function has the same name
   as ours in `aliases`/`zshrc`. Decide with the user which one wins. Removed
   names (`-` lines) matter only if our files use them.
6. Section 5: if `custom/example.zsh` differs, copy the OMZ version into
   `settings/osx/home/oh-my-zsh/custom/` so the two stay the same.
7. Section 7: commit only if a step above changed a file in this repo.

## Report

One `ОМ<n>` line per change that touches us: what changed, whether it clashes
or affects our options, and the action (usually "Не е нужно нищо"). Last line:
the state of `~/bin` (clean, or what to commit).

"Nothing to copy, nothing to commit" is the normal result. Say it plainly in
the first sentence, even when the user asked to "sync" files.

## Not part of this check

- `settings/linux/home/zsh/*` are old standalone copies (zsh-z,
  syntax-highlighting, history-substring-search) for the Linux setup without
  OMZ plugins. They do not follow OMZ updates.
- `stty: stdin isn't a terminal` from `zsh -i -c` is harmless.

## Common mistakes

| Mistake | Fix |
|---|---|
| Checking plugin load through `$fpath` | Many plugins add no fpath entry. Check the `.plugin.zsh` file in `$ZSH_CUSTOM/plugins` or `$ZSH/plugins` (check.sh does this). |
| Reading only `--stat` | Read the diff of each used plugin; option-related fixes (e.g. `noclobber`) hide in small changes. |
| Grepping custom plugin sources for clashes | Vendored plugin files mention many alias names; check only our own files. |
