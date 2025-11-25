defmodule ExAzureCore.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ExAzureCore.Auth.Registry
    ]

    opts = [strategy: :one_for_one, name: ExAzureCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
