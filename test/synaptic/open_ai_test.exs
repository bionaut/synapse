defmodule Synaptic.Tools.OpenAITest do
  use ExUnit.Case, async: true

  alias Synaptic.Tools.OpenAI

  test "parse_response returns plain text content" do
    body = completion_body(%{"content" => "hello"})

    assert {:ok, "hello"} = OpenAI.parse_response(body)
  end

  test "parse_response decodes json when response_format requests objects" do
    body = completion_body(%{"content" => ~s({"foo":"bar"})})

    assert {:ok, %{"foo" => "bar"}} =
             OpenAI.parse_response(body, response_format: :json_object)
  end

  test "parse_response flattens list content payloads" do
    message = %{
      "content" => [
        %{"type" => "text", "text" => "hello"},
        %{"text" => " world"}
      ]
    }

    assert {:ok, "hello world"} = OpenAI.parse_response(completion_body(message))
  end

  test "parse_response surfaces tool calls" do
    message = %{
      "content" => nil,
      "tool_calls" => [
        %{
          "id" => "call_1",
          "function" => %{
            "name" => "echo",
            "arguments" => ~s({"text":"hi"})
          }
        }
      ]
    }

    assert {:ok, %{content: nil, tool_calls: [%{"id" => "call_1"} | _]}} =
             OpenAI.parse_response(completion_body(message))
  end

  test "parse_response errors when json response is invalid" do
    body = completion_body(%{"content" => "oops"})

    assert {:error, :invalid_json_response} =
             OpenAI.parse_response(body, response_format: %{type: "json_object"})
  end

  defp completion_body(message) do
    Jason.encode!(%{
      "choices" => [
        %{"message" => message}
      ]
    })
  end
end
