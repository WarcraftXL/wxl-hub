<div align="center">

<img src="assets/logo.png" width="96" alt="">

# wxl-hub

**The desktop front door to WarcraftXL.** An extension store, a profile manager and a game launcher,
with a developer side that drives the asset pipeline without a terminal.

[![build](https://github.com/iThorgrim/wxl-hub/actions/workflows/build.yml/badge.svg)](https://github.com/iThorgrim/wxl-hub/actions/workflows/build.yml)
[![license](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](LICENSE)
![platform](https://img.shields.io/badge/platform-Windows%2010%2F11-lightgrey)
![javascript](https://img.shields.io/badge/hand--written%20JS-0%20lines-brightgreen)

Think Vortex, scoped to WarcraftXL, and written entirely in Lua.

</div>

## What it does

- **Browse and install extensions.** The catalogue is read from GitHub at every launch: one search
  for the `wxl-modules` topic, then that repository's own `wxl.json`. Installing unpacks a release
  asset into `Extensions\<id>\` and records every file it wrote.
- **Keep them straight.** The library shows what is deployed, at which version, and whether the
  catalogue has moved past it. Turning a module off renames its folder so the core skips it, because
  a column claiming something the core disagrees with is not a switch.
- **Launch the game.** From the folder the active profile points at, with the client's own cache
  cleared first if you asked for that.
- **Profiles.** A profile owns the client you launch and the paths that go with it. Everything that
  describes you rather than a client follows you across all of them.
- **Say what is happening.** Downloads report a real rate and a real remaining time, and anything
  that finished while you were on another page is waiting in the notification centre.

## Why not Electron

An Electron shell ships around 150 MB of Chromium per app. `wxl-hub` renders through **WebView2**,
already present on Windows 10 and 11, so the whole application is one LuaJIT executable plus three
small DLLs. The interface is HTML and CSS driven by **htmx**, which means **no Node, no npm,**
**no bundler and no hand-written JavaScript** in the toolchain. Every line of application logic is Lua.

The two functions in `views/layout.etlua` are the exception that proves it: one scrolls a rail, the
other opens the native folder dialog. Neither holds state and neither talks to the server.

## The store has no server

There is no registry to run and no account to create. A repository joins the catalogue by carrying
the GitHub topic `wxl-modules` and a `wxl.json` at its root:

```jsonc
{
  "manifest": 1,
  "extension": {
    "id": "wxl-modern-adt",
    "version": "1.0.0",
    "abi": "1.1",
    "entry": "wxl-modern-adt.dll",
    "hooks": [ { "target": "Adt.TileAreaLoad" } ]
  },
  "deploy": { "mode": "release", "match": "*.zip" },
  "listing": {
    "title": "Modern ADT",
    "tagline": "Reads split terrain tiles straight into the client.",
    "description": "store/description.md",
    "cover": "store/cover.png"
  }
}
```

No manifest, no listing. Without one there is no id, no version and no statement of what installing
it would do, so the card could only be a name and a guess.

`deploy.mode` says where the binary comes from: `release` picks an asset off the latest GitHub
release, `shipped` takes a path committed in the repository, and `source` means the module is built
locally against a wxl-core checkout and the hub will not pretend otherwise.

Every path in a listing is repo-relative and validated before it becomes a URL. A manifest can point
at a file in its own repository and nowhere else, because listing content renders in the same
document that holds the hub's session token.

## Running it

```powershell
.\run.ps1            # from source, templates re-read as you edit them
.\build.ps1          # -> build\wxl-hub.exe, a single file
.\build.ps1 -Compile # bytecode-compiled: smaller, faster to start
.\build.ps1 -Run     # build, then launch it
```

The build appends the application to a luvi binary as a zip, stamps the icon and flips the PE
subsystem so no console appears. On first launch the executable unpacks itself under
`%LOCALAPPDATA%\WarcraftXL\hub\<version>\` and runs from there, because a DLL cannot be loaded out of
an archive and the worker thread cannot read the bundle at all.

## How it is put together

```
main.lua              entry point: unpack if bundled, then start
core/                 the framework, and the only code that knows about more than one module
  app.lua             wiring, the two threads, the routes that live in the shell
  server.lua          HTTP on 127.0.0.1, token-gated, nothing else may speak to it
  router.lua          /store/:id patterns, most-specific-first
  modules.lua         discovery, migrations, mounting
  mediator.lua        how modules reach each other without knowing each other
  view.lua            etlua, scoped per module
  page.lua            the shell, and the content security policy
  jobs.lua            background work on libuv's threadpool, and its progress
  install.lua         download, stage, verify, swap
  manifest.lua        parse and validate wxl.json, never raising on author input
ffi/                  sqlite3, WinHTTP, WebView2, the folder dialog, version resources
modules/<id>/         module.lua, routes.lua, views/, migrations/, models/
views/                shared partials
```

A module is a directory. The loader reads its declaration, applies its migrations, lets it register
routes and adds it to the navigation; adding a feature is dropping a folder in. Nothing holds a list
of what exists, which is why `parked = true` in a `module.lua` takes a page out of the app without a
single other file learning about it.

Modules never import each other. They publish capabilities and fill in collection points:

```lua
mediator.provide("catalogue.get", function(id) return cat().get(id) end)
mediator.contribute("home.section", { id = "store", order = 20, render = rail })

local row = mediator.ask("catalogue.get", id)   -- nil when no store is installed
```

`ask` returns nil when nothing provides the name, so a hub with the store removed still lists what
you have installed rather than raising. That is the whole point: the home page does not know the
store exists, and the core does not know profiles do.

## License

GPL-3.0-or-later, matching the rest of WarcraftXL. See [LICENSE](LICENSE).
