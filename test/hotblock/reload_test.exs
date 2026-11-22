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
  # one function, version/0, that returns the given number.
  defp write_version(dir, module, version) do
    forms = [
      {:attribute, 1, :module, module},
      {:attribute, 1, :export, [version: 0]},
      {:function, 1, :version, 0, [{:clause, 1, [], [], [{:integer, 1, version}]}]}
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

      assert Reload.load_modules([module]) == [module]
      assert loaded_version(module) == 2
    end

    test "can load the same module again after it was reloaded once",
         %{dir: dir, module: module} do
      write_version(dir, module, 1)
      {:module, ^module} = :code.load_file(module)

      write_version(dir, module, 2)
      Reload.load_modules([module])
      write_version(dir, module, 3)

      assert Reload.load_modules([module]) == [module]
      assert loaded_version(module) == 3
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
end
