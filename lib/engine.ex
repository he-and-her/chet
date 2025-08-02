defmodule Engine do
  use GenServer

  alias Chet.Sim
  alias __MODULE__, as: Engine

  def start_link(_opts), do: GenServer.start_link(Engine, nil, name: Engine)

  def init(_), do: {:ok, Sim.new_simulation()}

  def get_state, do: GenServer.call(Engine, :get_state)

  def tick, do: GenServer.cast(Engine, :tick)

  def reset(seed \\ nil), do: GenServer.cast(Engine, {:reset, seed})

  def force_set(sim), do: GenServer.cast(__MODULE__, {:force_set, sim})

  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_cast({:reset, seed}, _state) do
    new_state = Sim.new_simulation(seed)

    IO.puts("🌍 Simulation reset with seed: #{inspect(seed)}")

    IO.puts(
      "🌍 New simulation started with #{map_size(new_state.zones)} zones and #{map_size(new_state.beings)} beings."
    )

    {:noreply, new_state}
  end

  def handle_cast({:force_set, sim}, _), do: {:noreply, sim}

  def handle_cast(:tick, state) do
    new_state = Sim.tick(state)
    {:noreply, new_state}
  end
end
