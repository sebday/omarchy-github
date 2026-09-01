# Omarchy GitHub plugin

![Bar panel](preview.png)

Bar widget for GitHub contributions: today's count, 30-day stats, an activity heatmap, and local dirty repos under folders you choose on first open.

## Install

```bash
omarchy plugin add https://github.com/sebday/omarchy-github.git
omarchy plugin enable evo.github
```

A local path works the same way. Plugins run as unsandboxed code inside `omarchy-shell`. Review the files before enabling.

## Requirements

- `curl`, `jq`, and `bash` on `PATH`
- GitHub auth via `gh` or `pass` (see below)

## Auth

Resolution order:

1. `gh auth token` when the GitHub CLI is installed and logged in
2. `pass` at `omarchy/github/token`

```bash
# Easiest: sign in with the GitHub CLI (gh must be on PATH for the bar)
gh auth login

# Optional pass fallback
pass insert omarchy/github/token
```

## Settings

```bash
omarchy bar set evo.github refreshMinutes 15 --json
```

| Key | Default | What it does |
|---|---|---|
| `refreshMinutes` | `15` | Background refresh interval for contributions and repos |
| `repoRoots` | unset | Folders to scan for dirty git repos (set on first open or manually) |

## Local repos

On first open, the panel detects `~/projects`, `~/Projects`, `~/work`, and `~/Work` and asks which folders to scan. Until you save, no repo scan runs.

You can also configure roots manually in `shell.json` on the `evo.github` bar entry:

```json
{
  "id": "evo.github",
  "repoRoots": [
    { "path": "/home/you/projects", "label": "projects" },
    { "path": "/home/you/work", "label": "work" }
  ]
}
```

Or from the shell:

```bash
omarchy bar set evo.github repoRoots '[{"path":"/home/you/projects","label":"projects"}]' --json
```

(`--json` must come after the value.)

## IPC

```bash
omarchy-shell evo.github toggle
omarchy-shell evo.github refresh
omarchy-shell shell toggle evo.github
```

| Call | Action |
|---|---|
| `open` / `show` | Open the panel |
| `close` / `hide` | Close the panel |
| `toggle` | Toggle the panel |
| `refresh` | Refresh contributions and repos |
