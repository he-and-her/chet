defmodule Chet.Sim do
  alias Chet.{Zone, Meta, Message}

  defstruct zones: %{}, beings: %{}, day: 0, messages: []

  alias __MODULE__, as: Sim

  def new_simulation(seed \\ :rand.uniform(100_000)) do
    int_seed =
      case seed do
        s when is_binary(s) -> :erlang.phash2(s)
        s when is_integer(s) -> s
        _ -> :rand.uniform(100_000)
      end

    :rand.seed(:exsplus, {int_seed, int_seed + 1, int_seed + 2})

    zone_count = Enum.random(3..9)
    zone_names = Enum.take_random(?a..?z, zone_count) |> Enum.map(&String.to_atom(<<&1>>))

    zones =
      zone_names
      |> Enum.map(fn name ->
        {name, Zone.new(name, Enum.random(5..999))}
      end)
      |> Enum.into(%{})

    total_beings = Enum.random(5..117)

    all_roles = Meta.roles()

    {beings_map, updated_zones} =
      Enum.reduce(1..total_beings, {%{}, zones}, fn id, {being_map, zone_map} ->
        role = Enum.random(all_roles)
        zone = Enum.random(Map.keys(zone_map))

        being = Meta.new(id, zone, role)
        updated_zone = Zone.add_being(zone_map[zone], id)

        {
          Map.put(being_map, id, being),
          Map.put(zone_map, zone, updated_zone)
        }
      end)

    %Sim{
      zones: updated_zones,
      beings: beings_map,
      messages: [],
      day: 0
    }
  end

  def tick(sim) do
    updated_sim =
      sim
      |> process_messages()
      |> apply_role_actions()
      |> apply_movement()
      |> apply_daily_needs()
      |> enforce_no_loneliness()
      |> increment_day()

    save_snapshot(updated_sim)
  end

  def prepare_actions(sim) do
    update = fn being ->
      case being.role do
        :scout -> Meta.plan_action(being, {:scout, :b})
        :messenger -> Meta.plan_action(being, {:message, :c, "Zone A needs help!"})
        _ -> Meta.plan_action(being, {:move, :b})
      end
    end

    beings = Enum.map(sim.beings, fn {id, b} -> {id, update.(b)} end) |> Enum.into(%{})
    %{sim | beings: beings}
  end

  def to_map(sim) do
    %{
      day: sim.day,
      zones:
        Enum.map(sim.zones, fn {name, z} ->
          {name, %{resources: z.resources, beings: z.beings}}
        end)
        |> Enum.into(%{}),
      beings:
        Enum.map(sim.beings, fn {id, b} ->
          {id,
           %{
             role: b.role,
             location: b.location,
             inbox: b.inbox,
             memory: b.memory,
             alive: b.alive,
             next_action: b.next_action
           }}
        end)
        |> Enum.into(%{}),
      messages: sim.messages
    }
  end

  def from_map(%{
        "day" => day,
        "zones" => raw_zones,
        "beings" => raw_beings,
        "messages" => raw_msgs
      }) do
    zones =
      Enum.map(raw_zones, fn {name, z} ->
        {String.to_atom(name),
         %Zone{name: String.to_atom(name), resources: z["resources"], beings: z["beings"]}}
      end)
      |> Enum.into(%{})

    beings =
      Enum.map(raw_beings, fn {id, b} ->
        next_action =
          if is_binary(b["next_action"]),
            do: String.to_atom(b["next_action"]),
            else: b["next_action"]

        {
          String.to_integer(id),
          %Meta{
            id: String.to_integer(id),
            location: String.to_atom(b["location"]),
            role: String.to_atom(b["role"]),
            inbox: b["inbox"],
            memory: atomize_keys_map(b["memory"]),
            alive: b["alive"],
            next_action: next_action
          }
        }
      end)
      |> Enum.into(%{})

    messages =
      Enum.map(raw_msgs, fn msg ->
        %Message{
          from: msg["from"],
          to_zone: String.to_atom(msg["to_zone"]),
          content: msg["content"],
          delay: msg["delay"],
          sender_role: String.to_atom(msg["sender_role"])
        }
      end)

    %Sim{day: day, zones: zones, beings: beings, messages: messages}
  end

  defp atomize_keys_map(map) do
    Enum.into(map, %{}, fn {k, v} ->
      {String.to_atom(k), v}
    end)
  end

  defp save_snapshot(sim) do
    path = "snapshots/day_#{sim.day}.json"
    File.write!(path, Jason.encode!(to_map(sim), pretty: true))
    sim
  end

  defp process_messages(%{messages: msgs, beings: beings} = sim) do
    {delivered, remaining} =
      Enum.split_with(msgs, fn m -> m.delay <= 0 end)

    new_beings =
      Enum.reduce(delivered, beings, fn msg, acc ->
        Enum.reduce(acc, acc, fn {id, being}, acc ->
          if being.location == msg.to_zone and being.alive do
            Map.put(acc, id, Meta.receive_message(being, msg))
          else
            acc
          end
        end)
      end)

    updated_msgs = Enum.map(remaining, fn msg -> %{msg | delay: msg.delay - 1} end)

    %{sim | messages: updated_msgs, beings: new_beings}
  end

  defp apply_role_actions(sim = %{beings: beings, zones: zones, messages: msgs}) do
    {new_beings, new_messages} =
      Enum.reduce(beings, {beings, msgs}, fn {id, being}, {b_acc, m_acc} ->
        case being.next_action do
          {:scout, zone} when being.role == :scout and being.alive ->
            # Add zone data to memory
            zone_data = Map.get(zones, zone)

            updated =
              Map.update!(
                being,
                :memory,
                &Map.put(&1, zone, %{
                  beings: length(zone_data.beings),
                  resources: zone_data.resources
                })
              )

            {Map.put(b_acc, id, updated), m_acc}

          {:message, to_zone, content} when being.role == :messenger and being.alive ->
            msg = Message.new(being.location, to_zone, content, :messenger)
            {b_acc, [msg | m_acc]}

          _ ->
            {b_acc, m_acc}
        end
      end)

    %{sim | beings: new_beings, messages: new_messages}
  end

  defp apply_movement(%{zones: zones, beings: beings} = sim) do
    Enum.reduce(beings, {zones, beings}, fn {id, being}, {z_acc, b_acc} ->
      case being.next_action do
        {:move, to_zone} when being.alive ->
          from_zone = being.location

          # Ensure cost
          z_acc = update_in(z_acc[from_zone].resources, &max(&1 - 1, 0))

          # Move being
          z_acc =
            z_acc
            |> Map.update!(from_zone, &Zone.remove_being(&1, id))
            |> Map.update!(to_zone, &Zone.add_being(&1, id))

          b_acc = Map.put(b_acc, id, %{being | location: to_zone, next_action: :stay})

          {z_acc, b_acc}

        _ ->
          {z_acc, Map.put(b_acc, id, %{being | next_action: :stay})}
      end
    end)
    |> then(fn {zones, beings} -> %{sim | zones: zones, beings: beings} end)
  end

  defp apply_daily_needs(sim = %{zones: zones, beings: beings}) do
    updated_zones =
      Enum.reduce(zones, %{}, fn {name, zone}, acc ->
        zone_beings = Enum.filter(beings, fn {_, b} -> b.location == name and b.alive end)
        total = Enum.count(zone_beings)

        cond do
          total > zone.resources ->
            # not enough resources, beings die
            {_survivors, _updated_beings} =
              kill_beings(beings, Enum.map(zone_beings, fn {id, _} -> id end))

            IO.puts("Beings died due to starvation at #{name}")
            acc |> Map.put(name, %{zone | resources: 0, beings: []})

          true ->
            acc |> Map.put(name, %{zone | resources: zone.resources - total})
        end
      end)

    %{sim | zones: updated_zones, beings: beings}
  end

  defp enforce_no_loneliness(sim = %{zones: zones, beings: beings}) do
    lone_ids =
      zones
      |> Enum.flat_map(fn {_zone, %{beings: ids}} ->
        case ids do
          [only_one] -> [only_one]
          _ -> []
        end
      end)

    updated_beings =
      Enum.reduce(lone_ids, beings, fn id, acc ->
        if Map.has_key?(acc, id), do: Map.put(acc, id, %{acc[id] | alive: false}), else: acc
      end)

    if lone_ids != [] do
      IO.puts("Lonely beings died: #{inspect(lone_ids)}")
    end

    %{sim | beings: updated_beings}
  end

  defp kill_beings(beings, ids) do
    updated =
      Enum.reduce(ids, beings, fn id, acc ->
        if Map.has_key?(acc, id) do
          Map.put(acc, id, %{acc[id] | alive: false})
        else
          acc
        end
      end)

    {:ok, updated}
  end

  defp increment_day(sim), do: %{sim | day: sim.day + 1}
end
