defmodule Chet.Zone do
  defstruct [:name, :resources, beings: []]

  alias __MODULE__, as: Zone

  def new(name, resources), do: %Zone{name: name, resources: resources}

  def add_being(zone, being_id), do: %{zone | beings: [being_id | zone.beings]}

  def remove_being(zone, being_id), do: %{zone | beings: List.delete(zone.beings, being_id)}
end
