defmodule Hotblock.Reload do
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
end
