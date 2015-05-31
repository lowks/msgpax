defmodule Msgpax.Unpacker.Transform do
  import Macro, only: [pipe: 3]

  defmacro deftransform(format, to: value) do
    quote do
      defp transform(<<unquote_splicing(format), rest::bytes>>, _opts) do
        {unquote(value), rest}
      end
    end
  end

  defmacro deftransform(format, do: block) do
    quote do
      defp transform(<<unquote_splicing(format), rest::bytes>>, opts) do
        unquote(pipe(quote(do: rest), pipe(quote(do: opts), block, 0), 0))
      end
    end
  end
end

defmodule Msgpax.UnpackError do
  defexception [:message]

  def exception({:extra_bytes, bin}) do
    %__MODULE__{message: "extra bytes follow after packet: #{inspect(bin)}"}
  end

  def exception({:invalid_format, bin}) do
    %__MODULE__{message: "invalid format: #{inspect(bin)}"}
  end

  def exception(:incomplete) do
    %__MODULE__{message: "packet is incomplete"}
  end
end

defmodule Msgpax.Unpacker do
  import __MODULE__.Transform

  def unpack(iodata, opts) do
    {value, rest} =
      IO.iodata_to_binary(iodata)
      |> transform(opts)

    {:ok, value, rest}
  catch
    :throw, reason ->
      {:error, reason}
  end

  def unpack!(iodata, opts) do
    case unpack(iodata, opts) do
      {:ok, value, rest} -> {value, rest}
      {:error, reason} ->
        raise Msgpax.UnpackError, reason
    end
  end

  deftransform [0xC0], to: nil
  deftransform [0xC2], to: false
  deftransform [0xC3], to: true

  # String
  deftransform [0b101::3, len::5, val::size(len)-bytes],      to: val
  deftransform [0xD9, len::integer, val::size(len)-bytes],    to: val
  deftransform [0xDA, len::16-integer, val::size(len)-bytes], to: val
  deftransform [0xDB, len::32-integer, val::size(len)-bytes], to: val

  # Binary
  deftransform [0xC4, len::integer, val::size(len)-bytes],    do: binary(val)
  deftransform [0xC5, len::16-integer, val::size(len)-bytes], do: binary(val)
  deftransform [0xC6, len::32-integer, val::size(len)-bytes], do: binary(val)

  # Float
  deftransform [0xCA, val::32-big-float], to: val
  deftransform [0xCB, val::64-big-float], to: val

  # Integer
  deftransform [0::1, val::7],  to: val
  deftransform [0xCC, val],     to: val
  deftransform [0xCD, val::16], to: val
  deftransform [0xCE, val::32], to: val
  deftransform [0xCF, val::64], to: val

  deftransform [0b111::3, val::5],             to: val - 0b100000
  deftransform [0xD0, val::signed-integer],    to: val
  deftransform [0xD1, val::16-signed-integer], to: val
  deftransform [0xD2, val::32-signed-integer], to: val
  deftransform [0xD3, val::64-signed-integer], to: val

  # Array
  deftransform [0b1001::4, len::4], do: list(len)
  deftransform [0xDC, len::16],     do: list(len)
  deftransform [0xDD, len::32],     do: list(len)

  # Map
  deftransform [0b1000::4, len::4], do: map(len)
  deftransform [0xDE, len::16],     do: map(len)
  deftransform [0xDF, len::32],     do: map(len)

  # Ext
  deftransform [0xD4, type, val::1-bytes],  do: ext(type, val)
  deftransform [0xD5, type, val::2-bytes],  do: ext(type, val)
  deftransform [0xD6, type, val::4-bytes],  do: ext(type, val)
  deftransform [0xD7, type, val::8-bytes],  do: ext(type, val)
  deftransform [0xD8, type, val::16-bytes], do: ext(type, val)

  deftransform [0xC7, len, type, val::size(len)-bytes],     do: ext(type, val)
  deftransform [0xC8, len::16, type, val::size(len)-bytes], do: ext(type, val)
  deftransform [0xC9, len::32, type, val::size(len)-bytes], do: ext(type, val)

  defp transform(<<bin, _::bytes>>, _opts),
    do: throw({:invalid_format, bin})

  defp transform(<<_::bits>>, _opts),
    do: throw(:incomplete)

  defp binary(rest, %{binary: true}, val),
    do: {Msgpax.binary(val), rest}

  defp binary(rest, _opts, val),
    do: {val, rest}

  defp list(rest, opts, len, acc \\ [])
  defp list(rest, _opts, 0, acc),
    do: {Enum.reverse(acc), rest}

  defp list(rest, opts, len, acc) do
    {val, rest} = transform(rest, opts)

    list(rest, opts, len - 1, [val | acc])
  end

  defp map(rest, opts, len, acc \\ [])
  defp map(rest, _opts, 0, acc),
    do: {Enum.into(Enum.reverse(acc), %{}), rest}

  defp map(rest, opts, len, acc) do
    {key, rest} = transform(rest, opts)
    {val, rest} = transform(rest, opts)

    map(rest, opts, len - 1, [{key, val} | acc])
  end

  defp ext(rest, opts, type, data) when type in 0..127 do
    {ext(type, data, opts), rest}
  end

  defp ext(type, data, %{ext: ext}) when is_atom(ext) do
    case ext.unpack(type, data) do
      {:ok, val} -> val
    end
  end

  defp ext(type, data, _opts) do
    %Msgpax.Ext{type: type, data: data}
  end
end
