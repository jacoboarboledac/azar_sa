defmodule Servidor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Servidor.RegistroSorteos},

      Servidor.SupervisorSorteos,

      Servidor.Central
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Servidor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
