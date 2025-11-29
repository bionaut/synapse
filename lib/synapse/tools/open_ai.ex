defmodule Synapse.Tools.OpenAI do
  @moduledoc """
  Minimal OpenAI chat client built on Finch.
  """

  @endpoint "https://api.openai.com/v1/chat/completions"

  @doc """
  Sends a chat completion request.
  """
  def chat(messages, opts \\ []) do
    body =
      %{
        model: model(opts),
        messages: messages,
        temperature: Keyword.get(opts, :temperature, 0)
      }
      |> maybe_put_tools(opts)

    headers =
      [
        {"content-type", "application/json"},
        {"authorization", "Bearer " <> api_key(opts)}
      ]

    request =
      Finch.build(:post, endpoint(opts), headers, Jason.encode!(body))

    case Finch.request(request, finch(opts)) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        parse_response(response_body)

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        {:error, {:upstream_error, status, safe_decode(response_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp model(opts) do
    opts[:model] || config(opts)[:model] || "gpt-4o-mini"
  end

  defp maybe_put_tools(body, opts) do
    case Keyword.get(opts, :tools) do
      nil -> body
      [] -> body
      tools -> Map.merge(body, %{tools: tools, tool_choice: "auto"})
    end
  end

  defp endpoint(opts), do: opts[:endpoint] || config(opts)[:endpoint] || @endpoint

  defp api_key(opts) do
    opts[:api_key] ||
      config(opts)[:api_key] ||
      System.get_env("OPENAI_API_KEY") ||
      raise "Synapse OpenAI adapter requires an API key"
  end

  defp finch(opts) do
    opts[:finch] || config(opts)[:finch] || Synapse.Finch
  end

  defp parse_response(body) do
    with {:ok, decoded} <- Jason.decode(body),
         [choice | _] <- Map.get(decoded, "choices", []),
         %{"message" => %{"content" => content} = message} <- choice do
      tool_calls = tool_calls_from(message)

      if tool_calls == [] do
        {:ok, content}
      else
        {:ok, %{content: content, tool_calls: tool_calls}}
      end
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp tool_calls_from(%{"tool_calls" => calls}) when is_list(calls), do: calls
  defp tool_calls_from(_), do: []

  defp safe_decode(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> body
    end
  end

  defp config(_opts), do: Application.get_env(:synapse, __MODULE__, [])
end
