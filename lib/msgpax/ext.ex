defmodule Msgpax.Ext do
  defstruct [:type, :data]
end

Code.require_file("/Users/lexmag/Code/ecto/lib/ecto/datetime.ex")

defmodule User do
  @opaque t :: %__MODULE__{
    name: binary,
    age: integer,
    created_at: Ecto.Date.t
  }
  @derive Msgpax.Packer
  defstruct [:name, :age, :created_at]

  def new() do
    {:ok, date} = Ecto.Date.load({1, 1, 1})
    %__MODULE__{name: "Joe", created_at: date}
  end
end

defimpl Msgpax.Packer, for: Ecto.Date do
  def transform(date) do
    {:ok, type, data} = App.Msgpax.Ext.pack(date)
    %Msgpax.Ext{type: type, data: data}
    |> @protocol.Msgpax.Ext.transform()
  end
end

defmodule App.Msgpax.Ext do
  def pack(%Ecto.Date{} = date) do
    {:ok, 2, Ecto.Date.to_string(date)}
  end

  def unpack(2, str) do
    Ecto.Date.cast(str)
  end
end
