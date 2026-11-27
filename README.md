# mjcf.nvim

MuJoCo **MJCF** support for Neovim: schema-aware completion and compiler-grade diagnostics.
Cross-reference completion for element names is the remaining layer.

> **Status: L1 (schema) + L3 (diagnostics) implemented; L2 (name completion) planned.**

## Why

MJCF is a rich XML dialect, and generic XML tooling only gets you part of the way:

- an XML language server can complete elements, attributes and enum values from a schema, but it
  knows nothing about MJCF's cross-references (`<actuator joint="…">`, `<light target="…">`,
  `<tendon>` order);
- a schema can only check so much — MuJoCo's own XSD is deliberately permissive and carries no
  `xs:key`/`xs:keyref`, so name typos and semantic mistakes pass validation and only fail at
  `MjModel.from_xml_path` time.

`mjcf.nvim` is three cooperating layers:

| Layer | Provides | Mechanism |
| --- | --- | --- |
| **Schema** | element / attribute / enum completion, hover docs, structural diagnostics | binds MuJoCo's official `mjcf.xsd` to `lemminx` via `xml.fileAssociations` |
| **References** | completion of declared `name`s for `joint=`, `body=`, `site=`, `material=`, `class=`, `mesh=`, … | a completion source scanning the buffer and its `<include>` chain (planned) |
| **Diagnostics** | real compile errors (undefined default class, `range` without `limited`, bad mesh path, …) with the exact line MuJoCo reports | compiles the on-disk file with `mujoco.MjModel.from_xml_path` on save |

## Decisions

### Schema pin

The vendored schema is MuJoCo **4.0.1** (`schema/mjcf-4.0.1.xsd`). `opts.schema_path` replaces the
`systemId` with another file. The XSD ships inside the plugin so setup stays offline: there is no
download, CDN, or network fetch at install or runtime.

### Which files are bound

Default associations are only `**/*.mjcf.xml` and `**/*.mujoco.xml`, built from
`schema.suffixes`. Patterns passed in `schema.globs` are appended; they do not replace those
suffixes. The default stays narrow so ROS launch files, URDF, and other XML are not checked
against the MJCF schema. A false binding is worse than no binding. Opt in with `globs` when a
tree really is MJCF under another name.

Existing `settings.xml.fileAssociations` entries (from your config or another plugin) are kept.
MJCF entries are appended and de-duplicated on `systemId` + `pattern`.

## Pre-implementation experiments

These three checks are still open. Their results decide follow-up defaults. This plugin does not
set lemminx `validation.*`.

| experiment | pass criterion | status |
| --- | --- | --- |
| lemminx glob semantics (`**` 是否跨层、匹配绝对路径还是 workspace 相对) | `**/*.mjcf.xml` 能命中子目录里的文件 | pending |
| MuJoCo error message matrix (8 classes) | 每类都能提出行号（本仓库 `tests/fixtures/` 已固化样本） | pending |
| schema 噪音水平 (对 `ur5e`/`franka_emika_panda`/`robotiq_2f85` 三个目录跑校验) | 误报 < 10 条/目录，否则 `validation` 默认关闭 | pending |

## Design constraints

These are requirements, not aspirations — they are the reason this plugin exists separately instead
of being a snippet in someone's `lua/plugins/`.

- **Self-configuring.** `setup()` registers the schema association and the diagnostics.
  No edits to `lspconfig`, `blink.cmp`, or `none-ls` are required.
- **No ambient pollution.** Own `augroup` (`clear = true`), own diagnostic namespace
  (`mjcf.diagnostics`), `:Mjcf*`-prefixed commands, no global options, no `<leader>` keys.
  Compile autocmds are buffer-local, and only on buffers judged to be MJCF.
- **Diagnostics by content, schema by suffix.** A buffer is compiled when its first 200 lines
  contain a `<mujoco` root (filetype `xml` or empty), or when the name ends in `.mjcf.xml` /
  `.mujoco.xml`. Schema association uses those suffixes unless `schema.globs` adds patterns.
- **Offline.** The XSD ships with the plugin (pinned to MuJoCo 4.0.1); no CDN, no download at
  runtime.
- **Optional dependencies stay optional.** Missing `lemminx`, `blink.cmp`, or a Python `mujoco`
  install disables exactly one layer and leaves the rest working. `blink.cmp` is only relevant
  once L2 exists.

## Requirements

- Neovim ≥ 0.11 (`vim.lsp.config` deep-merged per-server config). Older versions skip L1.
- `lemminx` on `PATH` for the schema layer (for example installed through `mason.nvim`)
- Python with `mujoco` importable for the diagnostics layer (configurable command; `uv run` supported)
- Optional, later: `blink.cmp` for the reference-completion layer

## Installation

```lua
{
  "nirvana6/mjcf.nvim",
  ft = { "xml" },
  opts = {},
}
```

`setup()` deep-merges your table into the defaults, so you only write keys you want to change:

```lua
opts = {
  -- schema_path = "/absolute/path/to/other-mjcf.xsd",
  schema = {
    -- globs = { "**/*.xml" },
  },
  diagnostics = {
    -- python = "/path/to/.venv/bin/python",
    -- timeout = 20000,
  },
}
```

| key | default |
| --- | --- |
| `schema.enabled` | `true` |
| `schema.globs` | `{}` |
| `schema.suffixes` | `{ "*.mjcf.xml", "*.mujoco.xml" }` |
| `diagnostics.enabled` | `true` |
| `diagnostics.python` | `nil` (discover) |
| `diagnostics.timeout` | `20000` (milliseconds) |

Python discovery, cached until `DirChanged`:

1. `diagnostics.python`, when set
2. `.venv/bin/python` in the nearest ancestor that contains `pyproject.toml` or `.git`
3. `uv run --project <that dir> python`, when that directory has `pyproject.toml` and `uv` is on `PATH`
4. `python3`

A candidate is kept only if `import mujoco` succeeds. Otherwise the next one is tried.

## Diagnostics

MuJoCo compiles the file on disk (`MjModel.from_xml_path`). `<include>` paths are resolved
relative to that file, so an unsaved buffer is not compiled. Diagnostics run on `BufWritePost`
only and replace the previous set in the `mjcf.diagnostics` namespace. Results are reused when
the path, mtime, and size are unchanged. `:MjcfDiag` compiles immediately and skips that cache.

## Commands

- `:MjcfInfo` — layer status, schema path, whether the current buffer is MJCF, whether a compile is running
- `:MjcfRestart` — `:LspRestart lemminx` after association changes
- `:MjcfDiag` — compile the current buffer now
- `:checkhealth mjcf` — Neovim version, `lemminx`, bundled schema sha256, Python/`mujoco` probe, `blink.cmp` (L2 planned)

## Roadmap

- [x] Schema layer: vendor `mjcf-4.0.1.xsd`, register `fileAssociations`, pin the version
- [x] Diagnostics layer: `BufWritePost` compile, `line N` → diagnostic, mtime/size cache
- [ ] Reference layer: blink.cmp source with attribute-context routing and `<include>` resolution
- [x] `:MjcfInfo` — report which layers are active and why the others are not
- [x] Health check (`:checkhealth mjcf`)
- [x] Tests: headless Neovim fixtures for each implemented layer

## License

MIT — see [LICENSE](LICENSE).
