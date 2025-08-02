defmodule Chet.Meta do
  @roles [:scout, :messenger, :worker]

  defstruct [
    :id,
    :role,
    :location,
    :inbox,
    :memory,
    :alive,
    :next_action
  ]

  alias __MODULE__, as: Meta

  def new(id, location, role \\ :worker) do
    %Meta{
      id: id,
      role: role,
      location: location,
      inbox: [],
      memory: %{},
      alive: true,
      next_action: :stay
    }
  end

  def roles, do: @roles

  def plan_action(being, action), do: %{being | next_action: action}

  def receive_message(being, msg), do: %{being | inbox: [msg | being.inbox]}

  def forget_messages(being), do: %{being | inbox: []}
end
