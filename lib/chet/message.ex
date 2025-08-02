defmodule Chet.Message do
  defstruct [:from, :to_zone, :content, :delay, :sender_role]

  alias __MODULE__, as: Message

  def new(from, to_zone, content, sender_role) do
    %Message{
      from: from,
      to_zone: to_zone,
      content: content,
      # 1 tick delay
      delay: 1,
      sender_role: sender_role
    }
  end
end
