defmodule Hotblock.Reload do
  require Logger

  # The candidates whose .beam on disk differs from the loaded code
  def changed_modules(candidates) do
    modified = :code.modified_modules()
    Enum.filter(candidates, fn module -> module in modified end)
  end

  # Loads each module from disk and returns the ones that loaded
  def load_modules(modules) do
    Enum.filter(modules, fn module ->
      # removes code marked as old, but only if no processes linger in it
      :code.soft_purge(module)
      match?({:module, ^module}, :code.load_file(module))
    end)
  end

  def report([]), do: "Nothing to reload"

  def report([module]), do: "Reloaded 1 module: #{inspect(module)}"

  def report(modules) do
    modules_list = Enum.map_join(modules, ", ", &inspect/1)
    "Reloaded #{Enum.count(modules)} modules: #{modules_list}"
  end

  # Compiles the project and loads the proxy's modules that changed, without
  # restarting it. Run it from IEx: Hotblock.Reload.reload()
  def reload do
    case compile() do
      :ok ->
        modules =
          Application.spec(:hotblock, :modules)
          |> changed_modules()
          |> load_modules()

        Logger.info(report(modules))
        {:ok, modules}

      {:error, output} ->
        Logger.error("Compilation failed:\n" <> output)
        {:error, :compile_failed}
    end
  end

  # Compiles in another OS process, so the new .beam files are written to
  # _build but nothing is loaded yet
  defp compile do
    env = [{"MIX_ENV", to_string(Mix.env())}]

    case System.cmd("mix", ["compile"], env: env, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, output}
    end
  end
end
