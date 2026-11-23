# Hotblock

A proxy in Elixir between a Minecraft client and server. You can change its
code while you play, and the connection doesn't drop.

NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG
OR MICROSOFT.

## How it works

- Each player is a `Hotblock.Connection` process under a `DynamicSupervisor`.
  If one crashes, the others keep playing.
- The connection reads the packets, forwards them, and handles the
  `/hotblock:` commands.
- `Hotblock.Rules` decides what each command or effect sends. The chat and
  the panel both use it.
- `Hotblock.Reload` loads the new code and migrates the state of each
  connection.

## Setup

You need Elixir 1.20, and a Paper 26.1.2 server with these lines in
`server.properties`:

```
server-port=25566
online-mode=false
enforce-secure-profile=false
network-compression-threshold=-1
```

The proxy needs the packets without encryption or compression.

To spawn mobs, your player has to be an operator (`op <name>` in the server
console).

Then:

```
mix deps.get
iex -S mix
```

and join `localhost:25565` from Minecraft.

## Commands

| Command | What it does |
|---|---|
| `/hotblock:hello` | Says hello |
| `/hotblock:fx title <title> [\| <subtitle>]` | Shows a title |
| `/hotblock:fx actionbar <text>` | Shows a text above the hotbar |
| `/hotblock:fx weather clear\|rain\|thunder` | Changes the weather only for you |
| `/hotblock:fx bar <percent> <color> <text>` | Shows a boss bar |
| `/hotblock:fx bar off` | Removes the boss bar |
| `/hotblock:fx sound <sound>` | Plays a sound |
| `/hotblock:watch <entity> [radius]` | Warns you when that entity is close |
| `/hotblock:unwatch <entity>` | Stops the warning |
| `/hotblock:spawn <entity> [distance] [front\|behind\|left\|right]` | Spawns an entity next to you |
| `/hotblock:stats` | Shows the packets of your connection |
| `/hotblock:help` | Lists the commands |

## Control panel

Open `http://localhost:4000` while you play. From a phone, use your
computer's IP.

For kick and crash, start with a token and open `/admin`:

```
HOTBLOCK_ADMIN_TOKEN=secret iex -S mix
```

```
http://localhost:4000/admin?token=secret
```

## Hot reload

Change the code and run this in IEx:

```elixir
Hotblock.Reload.reload()
```

The players stay connected. This is what it does:

1. Compiles the project in a separate OS process, so a compile error doesn't
   stop the proxy.
2. Finds the modules that changed.
3. Pauses every connection with `:sys.suspend`, loads the new modules, and
   resumes them. Packets that arrive in the meantime wait in the process
   mailbox.
4. If `Hotblock.Connection` changed, it also updates the state of each
   connection with `code_change/3` before resuming it.

The state has a `version` field. `Hotblock.Connection.migrate/1` takes a state
from an older version to the current one, for example adding a new field with
a default value.

A process that is waiting inside a module keeps that version in use, like the
acceptor waiting for the next player. If an old version is still in use, the
reload is refused and nothing is loaded. The next section explains why.

### Two-version limit

The BEAM keeps at most two versions of a module loaded: the current one and
the old one. A process stays in the version it is running until it makes a
fully qualified call, like `__MODULE__.loop(state)`. The acceptor, waiting
for the next player inside `loop_acceptor`, only does that when a new player
connects.

Loading a third version removes the old one, and any process still running it
is killed. So two quick reloads, with no new player in between, kill the
acceptor. This is what happens with `recompile` in IEx.

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

## Tests

Stop `iex -S mix` first, because the tests use port 25565.

```
mix test
```
