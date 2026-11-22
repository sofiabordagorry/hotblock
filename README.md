# Hotblock

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `hotblock` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hotblock, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/hotblock>.


## Hot reload: the two-version limit

The BEAM keeps at most two versions of a module loaded: the current one and
the old one. A process stays in the version it is running until it makes a
fully qualified call, like `__MODULE__.loop(state)`. A proxy connection
waiting in `receive` only does that when its next packet arrives.

Loading a third version removes the old one, and any process still running it
is killed. So two quick reloads, with no packet in between, kick the player.
This is what happens with `recompile` in IEx.

To see it, run this script. It does not need Minecraft, and it gives the same
result every time:

```
mix run --no-start scripts/two_version_limit.exs
```

```
Without the guard
1. Version 1 loaded. A process waits for a message inside it
2. Version 2 loaded. The process is still in version 1, now the old one
3. Version 3 loaded after :code.purge/1
   The waiting process was killed: :killed

With Hotblock.Reload
1. Version 1 loaded. A process waits for a message inside it
2. Version 2 loaded. The process is still in version 1, now the old one
3. Reload refused: old code of :hotblock_reload_demo is still running. Nothing was loaded. Wait a moment and try again.
   The waiting process is alive: true
4. The process got its message and left. The same reload now loads version 3
```

`Hotblock.Reload.reload()` avoids it: before loading, it calls
`:code.soft_purge/1`, which only removes the old version if no process is
running it. If any module is still in use, it loads nothing and asks to try
again.
