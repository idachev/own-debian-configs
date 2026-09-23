# cc-sessions-supacode

Lists the running Claude Code sessions on this Mac and jumps to the
Supacode pane that hosts the chosen one. A background session
(`claude --bg`) has no pane, so it gets a new Supacode tab running
`claude attach <id>` in its repo.

Supacode only: focusing and opening tabs goes through the `supacode` CLI.

## Files

| Path | Purpose |
|---|---|
| `~/bin/cc-sessions-supacode` | The script. |

Needs `claude`, `jq`, `supacode` (installed with the Supacode app) and
`fzf` for the picker.

## Usage

```
cc-sessions-supacode              # fzf picker; Enter focuses / attaches
cc-sessions-supacode list         # table only
cc-sessions-supacode focus <q>    # no picker
```

`<q>` is tried in this order, and the first stage with a hit wins:

1. exact pid or background id (`94f31875`);
2. session id prefix;
3. case-insensitive substring of the session name.

More than one hit in a stage prints the candidates and exits with an
error instead of guessing.

Example table:

```
PID    KIND         STATUS   PANE      NAME                       CWD                                   SESSION
17992  background   idle     new-tab   review-queue-status-check  ~/develop/mentorano/digital-archives  94f31875
84391  interactive  waiting  supacode  continue-ocr-7e            ~/develop/mentorano/ocr-pipeline      fe4a8136
17037  interactive  idle     -         Проверка документация      ~/work/invenda/cocacola-japan         bc263c27
```

The `PANE` column says what Enter does:

| Value | Action |
|---|---|
| `supacode` | Brings Supacode to front and focuses the worktree, tab and split. |
| `new-tab` | Background session not shown anywhere: opens a new tab with `claude attach <id>`, titled with the session name. |
| `-` | Nothing to focus, e.g. a Claude Desktop session. |

## How it works

- **Sessions** come from `claude agents --json` (interactive and
  background).
- **Pane of a session.** Every Supacode terminal exports
  `TERM_PROGRAM=supacode`, `SUPACODE_WORKTREE_ID`, `SUPACODE_TAB_ID` and
  `SUPACODE_SURFACE_ID`. The script reads them from the `claude`
  process with `ps eww`, then checks with `supacode surface list` that
  the split still exists.
- **Background sessions** inherit that env from the shell that spawned
  them, even though they do not live there. That is why the env alone is
  not trusted: `TERM_PROGRAM` must be `supacode` and the surface must be
  alive. A background session that is already attached runs as a
  separate `claude attach <id>` process; the script finds it with
  `pgrep` and focuses that pane instead of opening a second tab.
- **Repo for a new tab.** The worktree whose path is the longest prefix
  of the session's `cwd`. If Supacode has none, the script adds the git
  root of the `cwd` (or the `cwd` itself outside git) with
  `supacode repo open`.

## Limits

- An archived worktree is ignored, so the repo is added again instead of
  unarchived.
- Claude Desktop sessions cannot be opened in a terminal.
- Only sessions of the current user are visible to `ps eww`.
