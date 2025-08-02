defmodule Chet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ChetWeb.Telemetry,
      Chet.Repo,
      {DNSCluster, query: Application.get_env(:chet, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Chet.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Chet.Finch},
      # Start a worker by calling: Chet.Worker.start_link(arg)
      # {Chet.Worker, arg},
      # Start to serve requests, typically the last entry
      {Engine, []},
      ChetWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Chet.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ChetWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
