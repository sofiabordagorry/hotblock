defmodule Hotblock.ReloadTest do
  # async: false because these tests load modules and change the code path,
  # which is global to the VM
  use ExUnit.Case, async: false

  alias Hotblock.Reload

  # Each test uses its own module, kept in a temporary folder on the code
  # path, like the proxy's modules in _build
  setup do
    dir = Path.join(System.tmp_dir!(), "hotblock_reload_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    :code.add_patha(String.to_charlist(dir))

    module = :"hotblock_reload_sample_#{System.unique_integer([:positive])}"

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
      :code.purge(module)
      :code.del_path(String.to_charlist(dir))
      File.rm_rf!(dir)
    end)

    %{dir: dir, module: module}
  end

  # Writes a version of the module to disk without loading it. The module has
  # version/0, which returns the given number, and wait/0, which blocks until
  # it gets :stop, like a connection waiting for a packet.
  defp write_version(dir, module, version) do
    forms = [
      {:attribute, 1, :module, module},
      {:attribute, 1, :export, [version: 0, wait: 0]},
      {:function, 1, :version, 0, [{:clause, 1, [], [], [{:integer, 1, version}]}]},
      {:function, 1, :wait, 0,
       [
         {:clause, 1, [], [],
          [{:receive, 1, [{:clause, 1, [{:atom, 1, :stop}], [], [{:atom, 1, :ok}]}]}]}
       ]}
    ]

    {:ok, ^module, binary} = :compile.forms(forms, [])
    File.write!(Path.join(dir, "#{module}.beam"), binary)
  end

  defp loaded_version(module), do: apply(module, :version, [])

  describe "changed_modules/1" do
    test "returns the modules whose file on disk is newer than the loaded code",
         %{dir: dir, module: module} do
      write_version(dir, module, 1)
      {:module, ^module} = :code.load_file(module)

      write_version(dir, module, 2)

      assert Reload.changed_modules([module]) == [module]
    end

    test "leaves out modules that did not change", %{dir: dir, module: module} do
      write_version(dir, module, 1)
      {:module, ^module} = :code.load_file(module)

      assert Reload.changed_modules([module]) == []
    end
  end

  describe "load_modules/1" do
    test "loads the new version from disk and returns the modules it loaded",
         %{dir: dir, module: module} do
      write_version(dir, module, 1)
      {:module, ^module} = :code.load_file(module)
      write_version(dir, module, 2)

      assert Reload.load_modules([module]) == {:ok, [module]}
      assert loaded_version(module) == 2
    end

    test "can load the same module again after it was reloaded once",
         %{dir: dir, module: module} do
      write_version(dir, module, 1)
      {:module, ^module} = :code.load_file(module)

      write_version(dir, module, 2)
      Reload.load_modules([module])
      write_version(dir, module, 3)

      assert Reload.load_modules([module]) == {:ok, [module]}
      assert loaded_version(module) == 3
    end

    test "refuses to load when a process still runs the old version, and does not kill it",
         %{dir: dir, module: module} do
      write_version(dir, module, 1)
      {:module, ^module} = :code.load_file(module)

      # A process waits inside version 1, then version 2 is loaded, so the
      # process keeps running what is now the old version
      waiting = spawn(module, :wait, [])
      write_version(dir, module, 2)
      {:ok, [^module]} = Reload.load_modules([module])

      # Loading version 3 would remove version 1 and kill the process
      write_version(dir, module, 3)

      assert Reload.load_modules([module]) == {:error, {:old_code_in_use, [module]}}
      assert Process.alive?(waiting)
      assert loaded_version(module) == 2
    end

    test "loads once the process has left the old version", %{dir: dir, module: module} do
      write_version(dir, module, 1)
      {:module, ^module} = :code.load_file(module)

      waiting = spawn(module, :wait, [])
      write_version(dir, module, 2)
      {:ok, [^module]} = Reload.load_modules([module])
      write_version(dir, module, 3)
      {:error, _} = Reload.load_modules([module])

      ref = Process.monitor(waiting)
      send(waiting, :stop)
      assert_receive {:DOWN, ^ref, :process, _, _}

      assert Reload.load_modules([module]) == {:ok, [module]}
      assert loaded_version(module) == 3
    end

    test "loads nothing if any of the modules is still in use", %{dir: dir, module: module} do
      other = :"#{module}_other"

      on_exit(fn ->
        :code.purge(other)
        :code.delete(other)
        :code.purge(other)
      end)

      for m <- [module, other], do: write_version(dir, m, 1)
      for m <- [module, other], do: {:module, ^m} = :code.load_file(m)

      # Only the first module has a process left in its old version
      spawn(module, :wait, [])
      for m <- [module, other], do: write_version(dir, m, 2)
      {:ok, _} = Reload.load_modules([module, other])
      for m <- [module, other], do: write_version(dir, m, 3)

      assert Reload.load_modules([module, other]) == {:error, {:old_code_in_use, [module]}}
      assert loaded_version(other) == 2
    end
  end

  describe "report/1" do
    test "lists the reloaded modules" do
      assert Reload.report([Hotblock.Rules, Hotblock.Commands]) ==
               "Reloaded 2 modules: Hotblock.Rules, Hotblock.Commands"
    end

    test "says module, not modules, for 1" do
      assert Reload.report([Hotblock.Rules]) == "Reloaded 1 module: Hotblock.Rules"
    end

    test "says so when nothing changed" do
      assert Reload.report([]) == "Nothing to reload"
    end
  end

  describe "refused_report/1" do
    test "names the modules that are still in use and says what to do" do
      assert Reload.refused_report([Hotblock.Proxy]) ==
               "Reload refused: old code of Hotblock.Proxy is still running. " <>
                 "Nothing was loaded. Wait a moment and try again."
    end

    test "lists several modules" do
      assert Reload.refused_report([Hotblock.Proxy, Hotblock.Rules]) ==
               "Reload refused: old code of Hotblock.Proxy, Hotblock.Rules is still running. " <>
                 "Nothing was loaded. Wait a moment and try again."
    end
  end
end
