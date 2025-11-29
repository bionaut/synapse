defmodule Synaptic.Tools.Tool do
  @moduledoc """
  Struct describing an LLM-callable tool.
  """

  @enforce_keys [:name, :description, :schema, :handler]
  defstruct [:name, :description, :schema, :handler]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          schema: map(),
          handler: (map() -> term())
        }

  @doc """
  Builds a tool struct from a keyword list or map.
  """
  def new(%__MODULE__{} = tool), do: tool

  def new(attrs) when is_list(attrs) do
    attrs |> Enum.into(%{}) |> new()
  end

  def new(%{name: name, description: description, schema: schema, handler: handler})
      when is_binary(name) and is_binary(description) and is_map(schema) and
             is_function(handler, 1) do
    %__MODULE__{name: name, description: description, schema: schema, handler: handler}
  end

  def new(other) do
    raise ArgumentError, "invalid tool definition: #{inspect(other)}"
  end

  @doc """
  Serializes the tool to an OpenAI-compatible payload.
  """
  def to_openai(%__MODULE__{} = tool) do
    %{
      type: "function",
      function: %{
        name: tool.name,
        description: tool.description,
        parameters: tool.schema
      }
    }
  end
end
