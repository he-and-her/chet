defmodule Chet.Repo do
  use Ecto.Repo,
    otp_app: :chet,
    adapter: Ecto.Adapters.Postgres
end
