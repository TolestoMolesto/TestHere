# PonchoGameRework

Dragon Ball-style Roblox fighting game (Ki, BattlePower, transformations, races). Mid-"Rework"
onto a new slot-based data model. `src/` is the source of truth.

## Toolchain (this is set up and working — do not say "there's no Luau CLI")

Sync is done with **Argon** (NOT Rojo), which reads the Rojo-format `default.project.json`.
CLI dev tools are managed by **Rokit** (`rokit.toml`), installed under `~/.rokit/bin`:

| Tool | Version | Purpose |
|------|---------|---------|
| StyLua | 2.5.2 | formatter (`stylua.toml`, `.styluaignore`) |
| selene | 0.31.0 | linter (`selene.toml`, Roblox std bundled) |
| luau-lsp | 1.68.0 | CLI type checker (`luau-lsp analyze`) |

`rojo` exists via aftman but is **unused and intentionally broken** — Argon replaces it. Ignore it.

### Verify code (use this instead of round-tripping through Studio)

```powershell
./check.ps1        # sourcemap + StyLua --check + selene + luau-lsp analyze
./check.ps1 -Fix   # auto-format with StyLua, then lint + type check
```

`check.ps1` regenerates `sourcemap.json` and downloads `globalTypes.d.luau` (Roblox API types,
gitignored) as needed. After a fresh clone: `rokit install`, then `./check.ps1`.

### Run / live-sync

```powershell
argon serve --sourcemap   # syncs src/ into Studio AND keeps sourcemap.json fresh for luau-lsp
```

The VS Code luau-lsp extension is configured (`.vscode/settings.json`) to read that sourcemap
rather than autogenerating one with the broken rojo.

## Conventions

- **Indentation: tabs.** Quotes: double. Most modules opt into `--!strict` per file.
- Combat/UI read stats **exclusively** from `Humanoid.Stats` folder attributes written by
  `StatsManager` — never from the profile directly.
- Entry point: `ServerScriptService/ProfileLoader.server.luau`. Health.server.luau self-destructs.

## Vendored code — do not lint/format/typecheck or "fix"

- `src/StarterPlayer/StarterPlayerScripts/PlayerModule/**` — stock Roblox camera/control scripts.
- `ProfileStore.luau` — 3rd-party data lib (loleris).

Both are excluded from all tooling. The remaining luau-lsp diagnostics are real and worth
addressing; the biggest theme is strict typing not knowing a `Model`'s children
(`char.HumanoidRootPart` → use `:FindFirstChild`/casts).
