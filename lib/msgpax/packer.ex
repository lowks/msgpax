defmodule Msgpax.PackError do
  defexception [:message]

  def exception({:too_big, term}) do
    %__MODULE__{message: "too big value: #{inspect(term)}"}
  end

  def exception({:badarg, term}) do
    %__MODULE__{message: "unprocessable value: #{inspect(term)}"}
  end
end

defprotocol Msgpax.Packer do
  def transform(term)

  Kernel.def pack(term) do
    {:ok, transform(term)}
  catch
    :throw, reason ->
      {:error, reason}
  end

  Kernel.def pack!(term) do
    case pack(term) do
      {:ok, bin} -> bin
      {:error, reason} ->
        raise Msgpax.PackError, reason
    end
  end

  Kernel.def ext(data, type) do
    Msgpax.Packer.Ext.transform(type, data)
  end
end

defimpl Msgpax.Packer, for: Atom do
  def transform(nil),   do: <<0xC0>>
  def transform(false), do: <<0xC2>>
  def transform(true),  do: <<0xC3>>
  def transform(atom) do
    Atom.to_string(atom)
    |> @protocol.transform
  end
end

defimpl Msgpax.Packer, for: BitString do
  def transform(bin) when is_binary(bin),
    do: [format(bin) | bin]

  def transform(bits), do: throw({:badarg, bits})

  defp format(bin) do
    size = byte_size(bin)
    cond do
      size < 32          -> <<0b101::3, size::5>>
      size < 256         -> <<0xD9, size::8>>
      size < 0x10000     -> <<0xDA, size::16>>
      size < 0x100000000 -> <<0xDB, size::32>>

      true -> throw {:too_big, bin}
    end
  end
end

defimpl Msgpax.Packer, for: Map do
  defmacro __deriving__(module, _, _opts) do
    quote do
      defimpl unquote(@protocol), for: unquote(module) do
        def transform(struct) do
          Map.from_struct(struct)
          |> @protocol.Map.transform
        end
      end
    end
  end

  def transform(map) do
    for {key, value} <- map, into: [format(map)] do
      [@protocol.transform(key) | @protocol.transform(value)]
    end
  end

  defp format(map) do
    len = Enum.count(map)
    cond do
      len < 16          -> <<0b1000::4, len::4>>
      len < 0x10000     -> <<0xDE, len::16>>
      len < 0x100000000 -> <<0xDF, len::32>>

      true -> throw {:too_big, map}
    end
  end
end

defimpl Msgpax.Packer, for: List do
  def transform([{}]), do: <<128>>
  def transform([{_, _} | _] = list),
    do: @protocol.Map.transform(list)

  def transform(list) do
    for elem <- list, into: [format(list)] do
      @protocol.transform(elem)
    end
  end

  defp format(list) do
    len = length(list)
    cond do
      len < 16          -> <<0b1001::4, len::4>>
      len < 0x10000     -> <<0xDC, len::16>>
      len < 0x100000000 -> <<0xDD, len::32>>

      true -> throw {:too_big, list}
    end
  end
end

defimpl Msgpax.Packer, for: Float do
  def transform(num) do
    <<0xCB, num::64-float>>
  end
end

defimpl Msgpax.Packer, for: Integer do
  def transform(num) when num < 0 do
    cond do
      num >= -32                 -> <<0b111::3, num::5>>
      num >= -128                -> <<0xD0, num>>
      num >= -0x8000             -> <<0xD1, num::16>>
      num >= -0x80000000         -> <<0xD2, num::32>>
      num >= -0x8000000000000000 -> <<0xD3, num::64>>

      true -> throw {:too_big, num}
    end
  end

  def transform(num) do
    cond do
      num < 128                 -> <<0::1, num::7>>
      num < 256                 -> <<0xCC, num>>
      num < 0x10000             -> <<0xCD, num::16>>
      num < 0x100000000         -> <<0xCE, num::32>>
      num < 0x10000000000000000 -> <<0xCF, num::64>>

      true -> throw {:too_big, num}
    end
  end
end

defimpl Msgpax.Packer, for: Msgpax.Binary do
  def transform(%{data: bin}) when is_binary(bin),
    do: [format(bin) | bin]

  defp format(bin) do
    size = byte_size(bin)
    cond do
      size < 256         -> <<0xC4, size::8>>
      size < 0x10000     -> <<0xC5, size::16>>
      size < 0x100000000 -> <<0xC6, size::32>>

      true -> throw {:too_big, bin}
    end
  end
end

defmodule Msgpax.Packer.Ext do
  def transform(type, data)
      when type in 0..127 and is_binary(data) do
    [format(data), type, data]
  end

  def transform(type, _data),
    do: throw({:badarg, type: type})

  def format(data) do
    size = byte_size(data)
    cond do
      size == 1          -> <<0xD4>>
      size == 2          -> <<0xD5>>
      size == 4          -> <<0xD6>>
      size == 8          -> <<0xD7>>
      size == 16         -> <<0xD8>>
      size < 256         -> <<0xC7, size>>
      size < 0x10000     -> <<0xC8, size::16>>
      size < 0x100000000 -> <<0xC9, size::32>>

      true -> throw {:too_big, data}
    end
  end
end


defimpl Msgpax.Packer, for: Reference do
  def transform(ref) do
    :erlang.term_to_binary(ref)
    |> @protocol.ext(0)
  end
end
