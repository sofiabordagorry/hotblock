defmodule Hotblock.Reload do
  require Logger

  # The candidates whose .beam on disk differs from the loaded code
  def changed_modules(candidates) do
    modified = :code.modified_modules()
    Enum.filter(candidates, fn module -> module in modified end)
  end

  # Loads each module from disk and returns the ones that loaded
  def load_modules(modules) do
    # soft_purge/1 removes code marked as old, but only if no processes linger in it
    case Enum.reject(modules, &:code.soft_purge/1) do
      [] ->
        loaded =
          Enum.filter(modules, fn module ->
            match?({:module, ^module}, :code.load_file(module))
          end)

        {:ok, loaded}

      in_use ->
        {:error, {:old_code_in_use, in_use}}
    end
  end

  def report([]), do: "Nothing to reload"

  def report([module]), do: "Reloaded 1 module: #{inspect(module)}"

  def report(modules) do
    modules_list = Enum.map_join(modules, ", ", &inspect/1)
    "Reloaded #{Enum.count(modules)} modules: #{modules_list}"
  end

  def refused_report(modules) do
    modules_list = Enum.map_join(modules, ", ", &inspect/1)

    "Reload refused: old code of #{modules_list} is still running. Nothing was loaded. Wait a moment and try again."
  end

  # Compiles the project and loads the proxy's modules that changed, without
  # restarting it. Run it from IEx: Hotblock.Reload.reload()
  def reload do
    case compile() do
      :ok ->
        loaded_modules =
          Application.spec(:hotblock, :modules)
          |> changed_modules()
          |> load_modules()

        case loaded_modules do
          {:ok, modules} ->
            Logger.info(report(modules))
            {:ok, modules}

          {:error, {:old_code_in_use, modules}} ->
            Logger.warning(refused_report(modules))
            {:error, {:old_code_in_use, modules}}
        end

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
