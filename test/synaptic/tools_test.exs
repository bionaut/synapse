defmodule Synaptic.ToolsTest do
  use ExUnit.Case

  defmodule PrimaryAdapter do
    def chat(_messages, opts), do: {:ok, {:primary, opts}}
  end

  defmodule SecondaryAdapter do
    def chat(_messages, opts), do: {:ok, {:secondary, opts}}
  end

  defmodule ToolAdapter do
    def chat(_messages, _opts) do
      case Process.get({__MODULE__, :stage}, :first) do
        :first ->
          Process.put({__MODULE__, :stage}, :second)

          {:ok,
           %{
             "content" => nil,
             "tool_calls" => [
               %{
                 "id" => "call_1",
                 "function" => %{
                   "name" => "echo",
                   "arguments" => ~s<{"text":"hi"}>
                 }
               }
             ]
           }}

        :second ->
          {:ok, "final"}
      end
    end
  end

  @messages [%{role: "user", content: "ping"}]

  setup do
    original = Application.get_env(:synaptic, Synaptic.Tools)

    Application.put_env(:synaptic, Synaptic.Tools,
      llm_adapter: __MODULE__.PrimaryAdapter,
      agents: [
        engineer: [model: "o4-mini", temperature: 0.2],
        translator: [adapter: __MODULE__.SecondaryAdapter, model: "gpt-4o-mini"]
      ]
    )

    on_exit(fn ->
      if original do
        Application.put_env(:synaptic, Synaptic.Tools, original)
      else
        Application.delete_env(:synaptic, Synaptic.Tools)
      end
    end)

    :ok
  end

  test "applies agent defaults" do
    assert {:ok, {:primary, opts}} = Synaptic.Tools.chat(@messages, agent: :engineer)
    assert opts[:model] == "o4-mini"
    assert opts[:temperature] == 0.2
  end

  test "allows explicit overrides" do
    assert {:ok, {:primary, opts}} =
             Synaptic.Tools.chat(@messages, agent: :engineer, temperature: 0.5)

    assert opts[:temperature] == 0.5
  end

  test "uses adapter overrides configured on agent" do
    assert {:ok, {:secondary, opts}} = Synaptic.Tools.chat(@messages, agent: :translator)
    assert opts[:model] == "gpt-4o-mini"
  end

  test "raises when agent is missing" do
    assert_raise ArgumentError, ~r/unknown Synaptic agent/, fn ->
      Synaptic.Tools.chat(@messages, agent: :missing)
    end
  end

  test "executes tools when adapter requests tool calls" do
    tool = %Synaptic.Tools.Tool{
      name: "echo",
      description: "echoes text",
      schema: %{
        type: "object",
        properties: %{text: %{type: "string"}},
        required: ["text"]
      },
      handler: fn %{"text" => text} ->
        Process.put(:tool_called, text)
        %{reply: text <> "!"}
      end
    }

    Process.delete({ToolAdapter, :stage})

    assert {:ok, "final"} =
             Synaptic.Tools.chat(@messages,
               adapter: ToolAdapter,
               tools: [tool]
             )

    assert Process.get(:tool_called) == "hi"
  end
end
