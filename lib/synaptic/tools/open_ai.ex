defmodule Synaptic.Tools.OpenAI do
  @moduledoc """
  Minimal OpenAI chat client built on Finch.
  """

  @endpoint "https://api.openai.com/v1/chat/completions"

  @doc """
  Sends a chat completion request.
  """
  def chat(messages, opts \\ []) do
    response_format =
      opts
      |> response_format()
      |> normalize_response_format()

    body =
      %{
        model: model(opts),
        messages: messages,
        temperature: Keyword.get(opts, :temperature, 0)
      }
      |> maybe_put_tools(opts)
      |> maybe_put_response_format(response_format)

    headers =
      [
        {"content-type", "application/json"},
        {"authorization", "Bearer " <> api_key(opts)}
      ]

    request =
      Finch.build(:post, endpoint(opts), headers, Jason.encode!(body))

    case Finch.request(request, finch(opts)) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        parse_response(response_body, response_format: response_format)

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

  defp maybe_put_response_format(body, nil), do: body
  defp maybe_put_response_format(body, response_format),
    do: Map.put(body, :response_format, response_format)

  defp endpoint(opts), do: opts[:endpoint] || config(opts)[:endpoint] || @endpoint

  defp api_key(opts) do
    opts[:api_key] ||
      config(opts)[:api_key] ||
      System.get_env("OPENAI_API_KEY") ||
      raise "Synaptic OpenAI adapter requires an API key"
  end

  defp finch(opts) do
    opts[:finch] || config(opts)[:finch] || Synaptic.Finch
  end

  @doc false
  def parse_response(body, opts \\ []) do
    response_format =
      opts
      |> Keyword.get(:response_format)
      |> normalize_response_format()

    with {:ok, decoded} <- Jason.decode(body),
         [choice | _] <- Map.get(decoded, "choices", []),
         %{"message" => message} <- choice,
         {:ok, content} <- decode_content(message_content(message), response_format) do
      tool_calls = tool_calls_from(message)

      if tool_calls == [] do
        {:ok, content}
      else
        {:ok, %{content: content, tool_calls: tool_calls}}
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_response}
    end
  end

  defp message_content(message) do
    content = Map.get(message, :content) || Map.get(message, "content")

    case content do
      list when is_list(list) -> Enum.map_join(list, "", &content_segment_to_binary/1)
      other -> other
    end
  end

  defp content_segment_to_binary(%{"text" => text}), do: text
  defp content_segment_to_binary(%{text: text}), do: text

  defp content_segment_to_binary(text) when is_binary(text), do: text
  defp content_segment_to_binary(_other), do: ""

  defp decode_content(nil, _response_format), do: {:ok, nil}

  defp decode_content(content, response_format) do
    if json_response_format?(response_format) do
      decode_json_content(content)
    else
      {:ok, content}
    end
  end

  defp decode_json_content(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> {:error, :invalid_json_response}
    end
  end

  defp decode_json_content(_content), do: {:error, :invalid_json_response}

  defp json_response_format?(%{"type" => type}) when type in ["json_object", "json_schema"], do: true
  defp json_response_format?(%{type: type}) when type in ["json_object", "json_schema"], do: true
  defp json_response_format?(_), do: false

  defp tool_calls_from(%{"tool_calls" => calls}) when is_list(calls), do: calls
  defp tool_calls_from(_), do: []

  defp response_format(opts) do
    opts[:response_format] || config(opts)[:response_format]
  end

  defp normalize_response_format(nil), do: nil

  defp normalize_response_format(:json_object), do: %{"type" => "json_object"}
  defp normalize_response_format("json_object"), do: %{"type" => "json_object"}

  defp normalize_response_format(:json_schema), do: %{"type" => "json_schema"}
  defp normalize_response_format("json_schema"), do: %{"type" => "json_schema"}

  defp normalize_response_format(%{} = format) do
    Enum.reduce(format, %{}, fn {key, value}, acc ->
      string_key = normalize_format_key(key)
      normalized_value = normalize_format_value(string_key, value)
      Map.put(acc, string_key, normalized_value)
    end)
  end

  defp normalize_response_format(format), do: format

  defp normalize_format_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_format_key(key) when is_binary(key), do: key
  defp normalize_format_key(key), do: to_string(key)

  defp normalize_format_value("type", value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_format_value(_key, value), do: value

  defp safe_decode(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> body
    end
  end

  defp config(_opts), do: Application.get_env(:synaptic, __MODULE__, [])
end
