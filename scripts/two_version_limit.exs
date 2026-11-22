# Reproduces the two-version limit on purpose, without Minecraft, so it gives
# the same result every time. Run it with:
#
#     mix run --no-start scripts/two_version_limit.exs

defmodule TwoVersionLimit do
  alias Hotblock.Reload

  @module :hotblock_reload_demo

  def run do
    dir = Path.join(System.tmp_dir!(), "hotblock_reload_demo")
    File.mkdir_p!(dir)
    :code.add_patha(String.to_charlist(dir)) # fake _build for testing purposes

    IO.puts("Without the guard")
    without_guard(dir)
    IO.puts("")
    IO.puts("With Hotblock.Reload")
    with_guard(dir)

    unload()
    :code.del_path(String.to_charlist(dir))
    File.rm_rf!(dir)
  end

  # Loads the third version like `recompile` does: purge the old version,
  # which kills any process still running it, then load
  defp without_guard(dir) do
    {waiting, ref} = old_version_in_use(dir)

    write_version(dir, 3)
    :code.purge(@module)
    {:module, @module} = :code.load_file(@module)
    IO.puts("3. Version 3 loaded after :code.purge/1")

    receive do
      {:DOWN, ^ref, :process, ^waiting, reason} ->
        IO.puts("   The waiting process was killed: #{inspect(reason)}")
    after
      1000 -> IO.puts("   The waiting process is still alive")
    end
  end

  # Loads the third version with Reload.load_modules/1, which refuses while
  # the old version is in use
  defp with_guard(dir) do
    {waiting, _ref} = old_version_in_use(dir)

    write_version(dir, 3)
    {:error, {:old_code_in_use, modules}} = Reload.load_modules([@module])
    IO.puts("3. " <> Reload.refused_report(modules))
    IO.puts("   The waiting process is alive: #{Process.alive?(waiting)}")

    send(waiting, :stop)
    Process.sleep(50)
    {:ok, _} = Reload.load_modules([@module])
    IO.puts("4. The process got its message and left. The same reload now loads version 3")
  end

  # Steps 1 and 2, the same for both runs: a process waits inside version 1,
  # then version 2 is loaded, so version 1 is now the old version and still
  # in use
  defp old_version_in_use(dir) do
    unload()

    write_version(dir, 1)
    {:module, @module} = :code.load_file(@module)
    waiting = spawn(@module, :wait, [])
    ref = Process.monitor(waiting)
    IO.puts("1. Version 1 loaded. A process waits for a message inside it")

    write_version(dir, 2)
    {:ok, _} = Reload.load_modules([@module])
    IO.puts("2. Version 2 loaded. The process is still in version 1, now the old one")

    {waiting, ref}
  end

  # Writes a version of the module to disk without loading it. version/0
  # returns the number, and wait/0 blocks until it gets :stop.
  defp write_version(dir, version) do
    forms = [
      {:attribute, 1, :module, @module},
      {:attribute, 1, :export, [version: 0, wait: 0]},
      {:function, 1, :version, 0, [{:clause, 1, [], [], [{:integer, 1, version}]}]},
      {:function, 1, :wait, 0,
       [
         {:clause, 1, [], [],
          [{:receive, 1, [{:clause, 1, [{:atom, 1, :stop}], [], [{:atom, 1, :ok}]}]}]}
       ]}
    ]

    {:ok, @module, binary} = :compile.forms(forms, [])
    File.write!(Path.join(dir, "#{@module}.beam"), binary)
  end

  # Removes both versions of the module, killing anything still running them
  defp unload do
    :code.purge(@module)
    :code.delete(@module)
    :code.purge(@module)
  end
end

TwoVersionLimit.run()
