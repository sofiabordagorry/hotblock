defmodule HotblockWeb.ErrorHTML do
  # The page for errors, like a 404: just the status, "Not Found"
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
