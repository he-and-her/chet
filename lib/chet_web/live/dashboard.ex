defmodule ChetWeb.DashboardLive do
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

  def handle_event("plan_action", %{"action" => action_map}, socket) do
    updated_beings =
      Enum.reduce(action_map, socket.assigns.sim.beings, fn {id_str, action_str}, acc ->
        id = String.to_integer(id_str)
        action = parse_action(action_str)

        if Map.has_key?(acc, id) do
          Map.put(acc, id, Chet.Meta.plan_action(acc[id], action))
        else
          acc
        end
      end)

    updated_sim = %{socket.assigns.sim | beings: updated_beings}
    {:noreply, assign(socket, sim: updated_sim)}
  end

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

  defp parse_action("stay"), do: :stay
  defp parse_action("move:" <> zone), do: {:move, String.to_atom(zone)}
  defp parse_action("scout:" <> zone), do: {:scout, String.to_atom(zone)}

  defp parse_action("message:" <> message) do
    [zone, content] = String.split(message, ":")
    {:message, String.to_atom(zone), content}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mt-4">
      <h3 class="font-semibold text-sm">🕰️ Seed History</h3>
      <ul class="list-disc list-inside text-sm text-gray-700">
        <%= for past <- @seed_history do %>
          <li class="cursor-pointer hover:underline" phx-click="reuse_seed" phx-value-seed={past}>
            {past}
          </li>
        <% end %>
      </ul>
    </div>

    <button
      type="button"
      phx-click="generate_seed"
      class="ml-2 px-3 py-1 rounded bg-indigo-600 text-white"
    >
      Random Cool Seed ✨
    </button>

    <p class="text-sm text-gray-600 italic">
      Active Seed: {@seed || "random"}
      <span
        id="copy"
        phx-hook="Clipboard"
        data-clipboard-value={@seed}
        class="ml-2 underline cursor-pointer text-blue-600 hover:text-blue-800"
      >
        📄 Copy Seed
      </span>
    </p>

    <div class="flex items-center space-x-4 mb-4">
      <button phx-click="tick" class="bg-blue-600 text-white px-4 py-2 rounded">Tick ⏩</button>
      <button phx-click="reset" class="bg-red-600 text-white px-4 py-2 rounded">Reset 🔄</button>
      <button phx-click="toggle_auto" class="bg-gray-600 text-white px-4 py-2 rounded">
        {if @auto_tick, do: "Pause ⏸️", else: "Auto Tick ▶️"}
      </button>
      <form phx-submit="reset_with_seed" phx-change="seed_typing">
        <input
          type="text"
          name="seed"
          value={@seed_input}
          placeholder="Enter seed..."
          class="border px-2 py-1 rounded text-sm"
        />
        <button type="submit" class="ml-2 px-3 py-1 rounded bg-purple-600 text-white">
          Seed Reset 🎲
        </button>
      </form>

      <a href="/export" class="px-3 py-1 bg-teal-600 text-white rounded shadow hover:bg-teal-700">
        📥 Export Simulation JSON
      </a>
      <form phx-submit="upload_snapshot">
        <.live_file_input upload={@uploads.snapshot} class="mt-2" />
        <button type="submit" class="ml-2 px-3 py-1 bg-orange-600 text-white rounded">
          📥 Import Snapshot (Live)
        </button>
      </form>
    </div>
    <div class="p-4 space-y-4">
      <h1 class="text-xl font-bold">🛰️ Simulation Day {@sim.day}</h1>

      <div class="grid grid-cols-3 gap-4">
        <%= for {zone_name, zone} <- @sim.zones do %>
          <div class="border rounded-xl p-3 shadow">
            <h2 class="font-semibold text-lg">Zone {to_string(zone_name)}</h2>
            <p>Resources: {zone.resources}</p>
            <p>Beings:</p>
            <ul class="list-disc list-inside">
              <%= for {_index, being} <- @sim.beings do %>
                <form phx-change="plan_action">
                  <select name={"action[#{being.id}]"} class="mt-2 border px-2 py-1 rounded">
                    <option value="stay" selected={being.next_action == :stay}>Stay</option>
                    <%= if being.role == :scout do %>
                      <option value="scout:b">Scout Zone B</option>
                      <option value="scout:c">Scout Zone C</option>
                    <% end %>
                    <%= if being.role == :messenger do %>
                      <option value="message:c:Help needed!">Message Zone C</option>
                      <option value="message:a:Warning!">Message Zone A</option>
                    <% end %>
                    <option value="move:b">Move to Zone B</option>
                    <option value="move:c">Move to Zone C</option>
                  </select>
                </form>
                <% being = @sim.beings[being.id] %>
                <li class="mt-2 border-t pt-2">
                  🧍‍♂️ ID: {being.id} | Role: {being.role}
                  <div class="text-sm mt-1 ml-2">
                    <p><strong>Memory:</strong></p>
                    <ul class="list-disc list-inside">
                      <%= for {z, data} <- being.memory do %>
                        <li>Zone {z}: {data.beings} beings, {data.resources} resources</li>
                      <% end %>
                    </ul>
                  </div>
                  <div class="text-sm mt-2 ml-2">
                    <p><strong>Inbox:</strong></p>
                    <ul class="list-disc list-inside">
                      <%= for msg <- being.inbox do %>
                        <li><em>"{msg.content}"</em> (from {msg.from})</li>
                      <% end %>
                    </ul>
                  </div>
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>
      </div>

      <div>
        <h2 class="text-lg font-semibold">📫 Pending Messages: {length(@sim.messages)}</h2>
        <ul>
          <%= for msg <- @sim.messages do %>
            <li>From: {msg.from} → {msg.to_zone} | “{msg.content}” (Delay: {msg.delay})</li>
          <% end %>
        </ul>
      </div>
    </div>

    <% stats = global_stats(@sim) %>

    <div class="border p-4 rounded bg-gray-50 shadow">
      <h2 class="text-lg font-bold mb-2">📊 Simulation Stats</h2>
      <p>Total Beings: {stats.total}</p>
      <p>Alive: {stats.alive} | Dead: {stats.dead}</p>
      <p>📨 Avg Inbox Size: {Float.round(stats.inbox_avg, 2)}</p>
      <p>🧠 Avg Memory Entries: {Float.round(stats.memory_avg, 2)}</p>
    </div>

    <h2 class="text-lg font-semibold">📊 Stats</h2>
    <div class="grid grid-cols-2 gap-4">
      <div>
        <h3 class="font-semibold">Resources by Zone</h3>
        <ul>
          <%= for {zone, data} <- zone_stats(@sim.zones, @sim.beings) do %>
            <li>
              {zone}:
              <span
                class="inline-block bg-green-500 h-4 align-middle"
                style={"width: #{data.resources * 10}px"}
              >
              </span>
              ({data.resources})
            </li>
          <% end %>
        </ul>
      </div>

      <div>
        <h3 class="font-semibold">Population by Zone</h3>
        <ul>
          <%= for {zone, data} <- zone_stats(@sim.zones, @sim.beings) do %>
            <li>
              {zone}:
              <span
                class="inline-block bg-blue-500 h-4 align-middle"
                style={"width: #{data.population * 20}px"}
              >
              </span>
              ({data.population})
            </li>
          <% end %>
        </ul>
      </div>
    </div>
    """
  end

  defp zone_stats(zones, _beings) do
    Enum.map(zones, fn {name, zone} ->
      pop = Enum.count(zone.beings)
      {name, %{resources: zone.resources, population: pop}}
    end)
  end

  defp global_stats(sim) do
    total = map_size(sim.beings)
    alive = Enum.count(sim.beings, fn {_id, b} -> b.alive end)
    dead = total - alive

    inbox_avg =
      sim.beings
      |> Map.values()
      |> Enum.map(&length(&1.inbox))
      |> then(&(Enum.sum(&1) / max(1, length(&1))))

    memory_avg =
      sim.beings
      |> Map.values()
      |> Enum.map(&map_size(&1.memory))
      |> then(&(Enum.sum(&1) / max(1, length(&1))))

    %{
      total: total,
      alive: alive,
      dead: dead,
      inbox_avg: inbox_avg,
      memory_avg: memory_avg
    }
  end

  defp generate_cool_seed do
    adjectives = ~w(lucky cosmic stormy velvet radiant chaotic tender ancient)
    nouns = ~w(moth dolphin signal thread whisper ember zone)
    "#{Enum.random(adjectives)}-#{Enum.random(nouns)}-#{Enum.random(100..999)}"
  end
end
