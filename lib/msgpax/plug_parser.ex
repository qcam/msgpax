if Code.ensure_compiled?(Plug) do
  defmodule Msgpax.PlugParser do
    @moduledoc """
    A `Plug.Parsers` plug for parsing a MessagePack-encoded body.

    Look at the [documentation for
    `Plug.Parsers`](http://hexdocs.pm/plug/Plug.Parsers.html) for more
    information on how to use `Plug.Parsers`.

    This parser accepts `unpacker` option as a module, function, and arguments
    tuple, to configure how unpacking should be done. Note that the response
    body will be prepended to the given list of arguments before applying.

    ## Examples

        defmodule MyPlugPipeline do
          use Plug.Builder

          plug Plug.Parsers,
               parsers: [Msgpax.PlugParser],
               pass: ["application/msgpack"]

          # Or use the :unpacker option.
          plug Plug.Parsers,
               parsers: [Msgpax.PlugParser],
               pass: ["application/msgpack"],
               unpacker: {Msgpax, :unpack!, [[binary: true, ...]]}

          # ... rest of the pipeline
        end

    """

    @behaviour Plug.Parsers

    import Plug.Conn

    def parse(%Plug.Conn{} = conn, "application", "msgpack", _headers, {unpacker, options}) do
      case read_body(conn, options) do
        {:ok, <<>>, conn} ->
          {:next, conn}

        {:ok, body, conn} ->
          {:ok, unpack_body(body, unpacker), conn}

        {:more, _partial_body, conn} ->
          {:error, :too_large, conn}
      end
    end

    def parse(%Plug.Conn{} = conn, _type, _subtype, _headers, _opts) do
      {:next, conn}
    end

    def init(options) do
      {unpacker, options} = Keyword.pop(options, :unpacker, Msgpax)

      validate_unpacker!(unpacker)

      {unpacker, options}
    end

    defp unpack_body(body, unpacker) do
      case apply_mfa_or_module(body, unpacker) do
        data when is_map(data) -> data
        data -> %{"_msgpack" => data}
      end
    rescue
      exception ->
        raise Plug.Parsers.ParseError, exception: exception
    end

    defp apply_mfa_or_module(body, {module_name, function_name, extra_args}) do
      apply(module_name, function_name, [body | extra_args])
    end

    defp apply_mfa_or_module(body, unpacker) do
      unpacker.unpack!(body)
    end

    defp validate_unpacker!({module, fun, args})
         when is_atom(module) and is_atom(fun) and is_list(args) do
      arity = length(args) + 1

      unless Code.ensure_compiled?(module) and function_exported?(module, fun, arity) do
        raise ArgumentError,
              "invalid :unpacker option. Undefined function " <>
                Exception.format_mfa(module, fun, arity)
      end
    end

    defp validate_unpacker!(unpacker) when is_atom(unpacker) do
      unless Code.ensure_compiled?(unpacker) do
        raise ArgumentError,
              "invalid :unpacker option. The module #{inspect(unpacker)} is not " <>
                "loaded and could not be found"
      end

      unless function_exported?(unpacker, :unpack!, 1) do
        raise ArgumentError,
              "invalid :unpacker option. The module #{inspect(unpacker)} must " <>
                "implement unpack!/1"
      end
    end

    defp validate_unpacker!(unpacker) do
      raise ArgumentError,
            "the :unpacker option expects a module, or a three-element " <>
              "tuple in the form of {module, function, extra_args}, got: #{inspect(unpacker)}"
    end
  end
end
