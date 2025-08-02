defmodule Chet do
  alias Chet.Sim

  def run do
    sim = Sim.new_simulation() |> Sim.prepare_actions()

    Enum.reduce(1..10, sim, fn _, acc ->
      IO.puts("Day #{acc.day}")

      acc
      |> Sim.prepare_actions()
      |> Sim.tick()
    end)
  end
end
