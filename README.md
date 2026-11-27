# mjcf.nvim

MuJoCo **MJCF** support for Neovim: schema-aware completion, cross-reference completion for
element names, and compiler-grade diagnostics — in one plugin, without touching your config.

> **Status: design stage.** Nothing here is implemented yet. This repository currently contains
> only the intended scope and the design constraints the implementation will be held to.

## Why

MJCF is a rich XML dialect, and generic XML tooling only gets you part of the way:

- an XML language server can complete elements, attributes and enum values from a schema, but it
  knows nothing about MJCF's cross-references (`<actuator joint="…">`, `<light target="…">`,
  `<tendon>` order);
- a schema can only check so much — MuJoCo's own XSD is deliberately permissive and carries no
  `xs:key`/`xs:keyref`, so name typos and semantic mistakes pass validation and only fail at
  `MjModel.from_xml_path` time.

`mjcf.nvim` is planned as three cooperating layers:

| Layer | Provides | Mechanism |
| --- | --- | --- |
| **Schema** | element / attribute / enum completion, hover docs, structural diagnostics | binds MuJoCo's official `mjcf.xsd` to `lemminx` via `xml.fileAssociations` |
| **References** | completion of declared `name`s for `joint=`, `body=`, `site=`, `material=`, `class=`, `mesh=`, … | a completion source scanning the buffer and its `<include>` chain |
| **Diagnostics** | real compile errors (undefined default class, `range` without `limited`, bad mesh path, …) with the exact line MuJoCo reports | compiles the buffer with `mujoco.MjModel.from_xml_path` on save |

## Design constraints

These are requirements, not aspirations — they are the reason this plugin exists separately instead
of being a snippet in someone's `lua/plugins/`.

- **Self-configuring.** Installing the plugin is the whole configuration: the schema association,
  the completion source and the diagnostics are registered from inside the plugin. No edits to
  `lspconfig`, `blink.cmp` or `none-ls` setups are required.
- **No ambient pollution.** Own `augroup` (`clear = true`), own diagnostic namespace, buffer-local
  mappings only, `:Mjcf*`-prefixed commands, no global options, no `<leader>` keys.
- **Detection by content, not by filename.** A buffer is MJCF when it contains a `<mujoco` root
  element — no `*.mjcf.xml` rename tax, and ROS launch/config XML is left alone.
- **Offline.** The XSD ships with the plugin (pinned to a MuJoCo version); no CDN, no download at
  runtime.
- **Optional dependencies stay optional.** Missing `blink.cmp` or a Python `mujoco` installation
  disables exactly one layer and leaves the rest working.

## Requirements

- Neovim ≥ 0.11 (`vim.lsp.config` deep-merged per-server config)
- `lemminx` on `PATH` for the schema layer (e.g. installed through `mason.nvim`)
- Python with `mujoco` importable for the diagnostics layer (configurable command; `uv run` supported)
- Optional: `blink.cmp` for the reference-completion layer

## Installation

Not installable yet — there is no code. Planned `lazy.nvim` spec:

```lua
{
  "nirvana6/mjcf.nvim",
  ft = { "xml" },
  opts = {},
}
```

## Roadmap

- [ ] Schema layer: vendor `mjcf.xsd`, register `fileAssociations`, document the per-version pin
- [ ] Diagnostics layer: `BufWritePost` compile, `line N` → diagnostic, mtime cache, debounce
- [ ] Reference layer: blink.cmp source with attribute-context routing and `<include>` resolution
- [ ] `:MjcfInfo` — report which layers are active and why the others are not
- [ ] Health check (`:checkhealth mjcf`)
- [ ] Tests: headless Neovim fixtures for each layer

## License

MIT — see [LICENSE](LICENSE).
