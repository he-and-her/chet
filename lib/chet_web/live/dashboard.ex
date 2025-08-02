defmodule ChetWeb.Dashboard do
  use ChetWeb, :live_view
  alias Engine

  alias Chet.Sim

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        sim: Engine.get_state(),
        auto_tick: true,
        planning: %{},
        seed: nil,
        seed_input: "",
        seed_history: []
      )
      |> allow_upload(:snapshot, accept: ~w(.json), max_entries: 1)

    if connected?(socket), do: :timer.send_interval(1000, self(), :maybe_tick)
    {:ok, socket}
  end

  @impl true
  def handle_info(:tick, socket) do
    Engine.tick()
    {:noreply, assign(socket, sim: Engine.get_state())}
  end

  def handle_info(:maybe_tick, socket) do
    if socket.assigns.auto_tick do
      Engine.tick()
      {:noreply, assign(socket, sim: Engine.get_state())}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("tick", _, socket) do
    Engine.tick()
    {:noreply, assign(socket, sim: Engine.get_state())}
  end

  def handle_event("reset", _, socket) do
    Engine.reset()
    {:noreply, assign(socket, sim: Engine.get_state())}
  end

  def handle_event("toggle_auto", _, socket),
    do: {:noreply, update(socket, :auto_tick, fn at -> not at end)}

  def handle_event("seed_typing", %{"seed" => seed}, socket),
    do: {:noreply, assign(socket, seed_input: seed)}

  def handle_event("reset_with_seed", %{"seed" => seed}, socket) do
    Engine.reset(seed)
    Process.sleep(50)

    new_history =
      [seed | socket.assigns.seed_history]
      |> Enum.uniq()
      |> Enum.take(10)

    {:noreply,
     assign(socket,
       sim: Engine.get_state(),
       seed: seed,
       seed_input: seed,
       seed_history: new_history
     )}
  end

  def handle_event("reuse_seed", %{"seed" => seed}, socket) do
    Engine.reset(seed)
    Process.sleep(50)

    {:noreply,
     assign(socket,
       sim: Engine.get_state(),
       seed: seed,
       seed_input: seed,
       seed_history: socket.assigns.seed_history
     )}
  end

  def handle_event("generate_seed", _, socket) do
    seed = generate_cool_seed()
    Engine.reset(seed)
    Process.sleep(50)

    new_history =
      [seed | socket.assigns.seed_history]
      |> Enum.uniq()
      |> Enum.take(10)

    {:noreply,
     assign(socket,
       sim: Engine.get_state(),
       seed: seed,
       seed_input: seed,
       seed_history: new_history
     )}
  end

  def handle_event("upload_snapshot", _params, socket) do
    consume_uploaded_entries(socket, :snapshot, fn %{path: path}, _entry ->
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, sim_map} ->
              sim_map |> Sim.from_map() |> Engine.force_set()
              {:ok, :ok}

            _ ->
              {:ok, :invalid_json}
          end

        _ ->
          {:ok, :read_error}
      end
    end)

    # ensure GenServer has applied state
    Process.sleep(50)

    {:noreply, assign(socket, sim: Engine.get_state())}
  end

  defp global_stats(sim) do
    total = map_size(sim.beings)
    alive = Enum.count(sim.beings, fn {_id, b} -> b.alive end)
    dead = total - alive

    %{
      total: total,
      alive: alive,
      dead: dead
    }
  end

  defp generate_cool_seed do
    adjectives = ~w(lucky cosmic stormy velvet radiant chaotic tender ancient)
    nouns = ~w(moth dolphin signal thread whisper ember zone)
    "#{Enum.random(adjectives)}-#{Enum.random(nouns)}-#{Enum.random(100..999)}"
  end
end
