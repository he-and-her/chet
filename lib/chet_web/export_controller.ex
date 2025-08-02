defmodule ChetWeb.ExportController do
  use ChetWeb, :controller

  alias Chet.Sim

  def export(conn, _params) do
    sim = Engine.get_state()
    json = sim |> Sim.to_map() |> Jason.encode!(pretty: true)

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=simulation_day_#{sim.day}.json"
    )
    |> send_resp(200, json)
  end

  def import(conn, %{"file" => %Plug.Upload{path: path}}) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, sim_map} ->
            sim_map |> Sim.from_map() |> Engine.force_set()

            conn
            |> put_flash(:info, "Simulation loaded successfully!")
            |> redirect(to: "/")

          _ ->
            send_resp(conn, 400, "Invalid JSON format")
        end

      _ ->
        send_resp(conn, 400, "Could not read file")
    end
  end
end
