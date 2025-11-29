defmodule Synapse.Tools do
  @moduledoc """
  Helper utilities for invoking LLM providers from workflow steps.
  """

  alias Synapse.Tools.Tool

  @default_adapter Synapse.Tools.OpenAI

  @doc """
  Dispatches a chat completion request to the configured adapter.

  Pass `agent: :name` to pull default options (model, temperature, adapter,
  etc.) from the `:agents` configuration. Provide `tools: [...]` with
  `%Synapse.Tools.Tool{}` structs (or maps/keywords convertible via
  `Synapse.Tools.Tool.new/1`) to enable tool-calling flows.
  """
  def chat(messages, opts \\ []) when is_list(messages) do
    {agent_opts, call_opts} = agent_options(opts)
    merged_opts = Keyword.merge(agent_opts, call_opts)

    {tools, merged_opts} = Keyword.pop(merged_opts, :tools, [])
    tool_specs = normalize_tools(tools)

    adapter = Keyword.get(merged_opts, :adapter, configured_adapter())

    adapter_opts =
      if tool_specs == [] do
        merged_opts
      else
        Keyword.put(merged_opts, :tools, Enum.map(tool_specs, &Tool.to_openai/1))
      end

    do_chat(adapter, messages, adapter_opts, tool_specs)
  end

  defp do_chat(adapter, messages, opts, []), do: adapter.chat(messages, opts)

  defp do_chat(adapter, messages, opts, tools) do
    tool_map = Map.new(tools, &{&1.name, &1})

    case adapter.chat(messages, opts) do
      {:ok, %{tool_calls: tool_calls} = message} when is_list(tool_calls) and tool_calls != [] ->
        new_messages = apply_tool_calls(messages, message, tool_map)
        do_chat(adapter, new_messages, opts, tools)

      {:ok, %{"tool_calls" => tool_calls} = message}
      when is_list(tool_calls) and
             tool_calls != [] ->
        new_messages = apply_tool_calls(messages, message, tool_map)
        do_chat(adapter, new_messages, opts, tools)

      other ->
        other
    end
  end

  defp agent_options(opts) do
    {agent_name, remaining_opts} = Keyword.pop(opts, :agent)

    agent_opts =
      case agent_name do
        nil -> []
        name -> lookup_agent_opts(name)
      end

    {agent_opts, remaining_opts}
  end

  defp lookup_agent_opts(name) do
    agents = configured_agents()
    key = agent_key(name)

    case Map.fetch(agents, key) do
      {:ok, opts} -> opts
      :error -> raise ArgumentError, "unknown Synapse agent #{inspect(name)}"
    end
  end

  defp configured_agents do
    Application.get_env(:synapse, __MODULE__, [])
    |> Keyword.get(:agents, %{})
    |> normalize_agents()
  end

  defp configured_adapter do
    Application.get_env(:synapse, __MODULE__, [])
    |> Keyword.get(:llm_adapter, @default_adapter)
  end

  defp normalize_agents(%{} = agents) do
    Enum.reduce(agents, %{}, fn {name, opts}, acc ->
      Map.put(acc, agent_key(name), normalize_agent_opts(opts))
    end)
  end

  defp normalize_agents(list) when is_list(list) do
    Enum.reduce(list, %{}, fn {name, opts}, acc ->
      Map.put(acc, agent_key(name), normalize_agent_opts(opts))
    end)
  end

  defp normalize_agents(_), do: %{}

  defp normalize_agent_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
    else
      raise ArgumentError, "agent options must be a keyword list, got: #{inspect(opts)}"
    end
  end

  defp normalize_agent_opts(%{} = opts) do
    opts
    |> Map.to_list()
    |> normalize_agent_opts()
  end

  defp normalize_agent_opts(other) do
    raise ArgumentError, "agent options must be a keyword list, got: #{inspect(other)}"
  end

  defp agent_key(name) when is_atom(name), do: Atom.to_string(name)

  defp agent_key(name) when is_binary(name) and byte_size(name) > 0, do: name

  defp agent_key(name) do
    raise ArgumentError, "agent names must be atoms or strings, got: #{inspect(name)}"
  end

  alias Synapse.Tools.Tool

  defp normalize_tools([]), do: []

  defp normalize_tools(tools) when is_list(tools) do
    Enum.map(tools, &Tool.new/1)
  end

  defp normalize_tools(tool), do: [Tool.new(tool)]

  defp apply_tool_calls(messages, message, tool_map) do
    assistant_msg = %{
      role: "assistant",
      content: Map.get(message, :content) || Map.get(message, "content"),
      tool_calls: Map.get(message, :tool_calls) || Map.get(message, "tool_calls")
    }

    tool_messages =
      assistant_msg.tool_calls
      |> Enum.map(&execute_tool_call(&1, tool_map))

    messages ++ [assistant_msg | tool_messages]
  end

  defp execute_tool_call(call, tool_map) do
    %{"function" => %{"name" => name, "arguments" => raw_args}, "id" => id} = call

    tool =
      Map.fetch!(tool_map, name)

    args =
      case Jason.decode(raw_args) do
        {:ok, decoded} -> decoded
        _ -> %{}
      end

    result = tool.handler.(args)

    %{
      role: "tool",
      tool_call_id: id,
      name: name,
      content: encode_tool_result(result)
    }
  end

  defp encode_tool_result(result) when is_binary(result), do: result
  defp encode_tool_result(result), do: Jason.encode!(result)
end
