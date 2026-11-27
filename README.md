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

## Installation

```lua
{
  "owner/mjcf.nvim",
  main = "mjcf",
  lazy = false,
  opts = {},
}
```

`lazy = false` is deliberate. The schema layer works by writing
`vim.lsp.config("lemminx", { settings = { xml = { fileAssociations = … } } })`, and lemminx reads
its configuration while the first XML client starts. A plugin spec gated on `ft = "xml"` (or any
`event`) can therefore run *after* that client is already up, and the schema silently misses the
first buffers until you run `:MjcfRestart`. The plugin itself is a few small Lua modules — loading
it at startup costs nothing measurable.

## Options

`setup()` deep-merges your table into the defaults below, so you only write the keys you want to
change. Every key is optional; `setup({})` is a valid configuration.

| key | type | default | effect |
| --- | --- | --- | --- |
| `schema_path` | string | bundled `schema/mjcf-4.0.1.xsd` | XSD to bind for file association |
| `schema.enabled` | boolean | `true` | register the association at all |
| `schema.suffixes` | list of string | `{ "*.mjcf.xml", "*.mujoco.xml" }` | filename patterns that opt a file into the schema |
| `schema.globs` | list of string | `{}` | extra glob patterns, passed to lemminx verbatim |
| `diagnostics.enabled` | boolean | `true` | content detection + compile-on-save |
| `diagnostics.python` | string | `nil` (auto-discover) | interpreter used to compile |
| `diagnostics.timeout` | number (ms) | `20000` | wall-clock cap for one compile |

### `schema_path`

Path to any MJCF XSD. Use an **absolute** path; a relative value is resolved against Neovim's
current working directory at setup time, which is rarely what you want (`~` is expanded). Point it
at a schema matching your MuJoCo version when you upgrade the simulator:

```lua
opts = { schema_path = vim.fn.expand("~/schemas/mjcf-4.1.0.xsd") }
```

The bundled file is MuJoCo 4.0.1, pinned by sha256. `:checkhealth mjcf` verifies that bundled hash;
an override is only checked for existence, never hashed — the plugin cannot know which MuJoCo
version your project uses.

### `schema.enabled`

`false` skips the `vim.lsp.config` call entirely: no association is registered, the bundled schema
is not read, and `:MjcfRestart` has nothing to reload. L3 keeps working independently.

### `schema.suffixes`

Filename patterns, not paths. Each entry is prefixed with `**/` before it reaches lemminx, so the
default two entries mean "any file whose name ends in `.mjcf.xml` or `.mujoco.xml`, at any depth".
Entries must be glob patterns (`*` is fine, but a bare `foo.xml` matches only that exact name).

Set it to `{}` to bind **no** filenames by default and rely on `schema.globs` alone — useful when a
project stores its models under a directory convention rather than a filename one.

### `schema.globs`

Additional patterns handed to lemminx **verbatim** — unlike `suffixes`, nothing is prefixed for
you, so write the full pattern you mean. They are *appended* to the suffix patterns; the two lists
never replace each other. Typical shapes:

```lua
opts = {
  schema = {
    globs = {
      "**/models/**/*.xml",       -- every XML below any models/ directory
      "**/robots/**/*.xml",
      "/opt/robot-models/**/*.xml", -- absolute pattern for a shared tree
    },
  },
}
```

Two properties are worth understanding before you add a pattern:

- **Matching is lemminx's job, not the plugin's.** The plugin only publishes the list. The exact
  glob dialect (`**` crossing directory boundaries, absolute versus workspace-relative matching) is
  lemminx's Java NIO glob, and is still being characterised in
  [issue #1](https://github.com/nirvana6/mjcf.nvim/issues/1). Prefer patterns that are unambiguous
  in any dialect.
- **The association is a lemminx-wide setting.** It cannot be scoped per buffer. `globs` chooses
  which *files* are matched against the MJCF schema; it does not switch the plugin on for one
  project and off for another. A pattern that is too broad is worse than no pattern: unrelated XML
  then gets MJCF completions and MJCF validation errors.

Existing `settings.xml.fileAssociations` entries (from your config or another plugin) are preserved:
MJCF entries are appended and de-duplicated on `systemId` + `pattern`. Note that arrays are
*replaced*, not merged, by `vim.tbl_deep_extend` — if some other plugin later sets
`settings.xml.fileAssociations` to its own list, that list wins. In that case merge by hand or set
your associations after the other plugin has run.

### `diagnostics.enabled`

`false` disables the whole L3 pipeline: no `BufReadPost`/`BufNewFile` detection autocmds are
registered, `vim.b[buf].mjcf` is never set, and `:MjcfDiag` refuses with an "diagnostics are
disabled" notice. L1 keeps working independently.

### `diagnostics.python`

A single **executable**, used as `argv[0]` — arguments are not accepted. This covers the common
cases (a venv interpreter, `python3`, a wrapper on `PATH`); if you need flags or an environment
bootstrap, point it at a small wrapper script:

```lua
opts = { diagnostics = { python = vim.fn.expand("~/bin/mujoco-python") } }
```

Leave it unset to let discovery run (below). Discovery results are cached until `DirChanged`.

### `diagnostics.timeout`

Milliseconds, applied to one compile. On expiry the child is killed and a single `WARN` diagnostic
replaces the buffer's diagnostics — the editor is never blocked waiting for MuJoCo. Compiling a
large scene with heavy meshes can legitimately take a second or two; raise it only if you see
spurious timeouts, since the value is the worst case the plugin waits before reporting.

### Full example

A fictional project that keeps models under `models/` and uses a pinned toolchain:

```lua
{
  "owner/mjcf.nvim",
  main = "mjcf",
  lazy = false,
  opts = {
    schema = {
      globs = { "**/models/**/*.xml" },
      suffixes = {},                        -- filenames carry no special suffix here
    },
    diagnostics = {
      python = vim.fn.expand("~/work/acme-robot/.venv/bin/python"),
      timeout = 10000,
    },
  },
}
```

## Which files are selected

Two independent decisions, made differently on purpose:

| | schema association (L1) | compile diagnostics (L3) |
| --- | --- | --- |
| decided by | path: `schema.suffixes` + `schema.globs` | content: `<mujoco` root in the first 200 lines (filetype `xml` or empty), or the two suffixes |
| scope | global lemminx setting | per buffer, `vim.b[buf].mjcf` |
| can rename a file to opt in | yes | not needed |

The asymmetry is the point: a file must be *identifiable by path* before a schema can be attached to
it, while MuJoCo's compiler only needs the content. So a plain `robot.xml` gets compile diagnostics
immediately and needs a `globs` entry (or a rename) to also get schema completion.

## Diagnostics

MuJoCo compiles the file on disk (`MjModel.from_xml_path`). `<include>` paths are resolved
relative to that file, so an unsaved buffer is not compiled. Diagnostics run on `BufWritePost`
only and replace the previous set in the `mjcf.diagnostics` namespace. Results are reused when
the path, mtime, and size are unchanged; the cache is per session and not evicted (entries are a
few bytes each). `:MjcfDiag` compiles immediately and skips that cache.

If no interpreter with an importable `mujoco` is found, the plugin notifies once per session and
stops trying — it does not re-warn on every save. Fix the interpreter and call
`require("mjcf").setup(...)` again (or restart Neovim) to retry.

## Runtime behaviour

- `vim.b[buf].mjcf` is `true` on buffers the plugin treats as MJCF; it is what `:MjcfInfo` reports.
- Compile autocmds are buffer-local and only attached to those buffers; `BufWipeout` clears the
  buffer's diagnostics and cancels an in-flight compile.
- A second write while a compile is running cancels the earlier job for that buffer.
- Changing `schema_path` / `schema.globs` / `schema.suffixes` at runtime requires re-running
  `setup()` **and** `:MjcfRestart` — lemminx only re-reads its configuration on restart.

## Commands

- `:MjcfInfo` — layer status, schema path, whether the current buffer is MJCF, whether a compile is running
- `:MjcfRestart` — `:LspRestart lemminx` after association changes
- `:MjcfDiag` — compile the current buffer now
- `:checkhealth mjcf` — Neovim version, `lemminx` executable *and* enabled, bundled schema sha256, Python/`mujoco` probe, `blink.cmp` (L2 planned)

## Design constraints

These are requirements, not aspirations — they are the reason this plugin exists separately instead
of being a snippet in someone's `lua/plugins/`.

- **Self-configuring.** `setup()` registers the schema association and the diagnostics.
  No edits to `lspconfig`, `blink.cmp`, or `none-ls` are required.
- **No ambient pollution.** Own `augroup` (`clear = true`), own diagnostic namespace
  (`mjcf.diagnostics`), `:Mjcf*`-prefixed commands, no global options, no `<leader>` keys.
  Compile autocmds are buffer-local, and only on buffers judged to be MJCF.
- **Offline.** The XSD ships with the plugin (pinned to MuJoCo 4.0.1); no CDN, no download at
  runtime.
- **Optional dependencies stay optional.** Missing `lemminx`, `blink.cmp`, or a Python `mujoco`
  install disables exactly one layer and leaves the rest working. `blink.cmp` is only relevant
  once L2 exists.

## Requirements

- Neovim ≥ 0.11 (`vim.lsp.config` deep-merged per-server config). Older versions skip L1.
- `lemminx` on `PATH` **and enabled** (`vim.lsp.enable("lemminx")`, or an installer such as
  `mason-lspconfig`'s automatic enable). Being on `PATH` alone does nothing; `:MjcfInfo` and
  `:checkhealth mjcf` report both halves separately.
- Python with `mujoco` importable for the diagnostics layer
- Optional, later: `blink.cmp` for the reference-completion layer

## Pre-implementation experiments

These three checks are still open. Their results decide follow-up defaults. This plugin does not
set lemminx `validation.*`.

| experiment | pass criterion | status |
| --- | --- | --- |
| lemminx glob semantics (`**` crossing directories, absolute vs workspace-relative) | `**/*.mjcf.xml` matches files in subdirectories | pending |
| MuJoCo error message matrix (8 classes) | every class yields an extractable line number (fixtures: `tests/fixtures/`) | pending |
| schema noise level on real model trees | fewer than ~10 false positives per tree, otherwise `validation` defaults to off | pending |

## Roadmap

- [x] Schema layer: vendor `mjcf-4.0.1.xsd`, register `fileAssociations`, pin the version
- [x] Diagnostics layer: `BufWritePost` compile, `line N` → diagnostic, mtime/size cache
- [ ] Reference layer: blink.cmp source with attribute-context routing and `<include>` resolution
- [x] `:MjcfInfo` — report which layers are active and why the others are not
- [x] Health check (`:checkhealth mjcf`)
- [x] Tests: headless Neovim fixtures for each implemented layer

## License

MIT — see [LICENSE](LICENSE).
