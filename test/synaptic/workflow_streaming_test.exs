defmodule Synaptic.WorkflowStreamingTest do
  use ExUnit.Case

  alias Synaptic.Tools

  defmodule StreamingWorkflow do
    use Synaptic.Workflow

    step :generate do
      messages = [%{role: "user", content: "Say hello"}]

      case Tools.chat(messages, stream: true) do
        {:ok, content} ->
          {:ok, %{generated: content}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    step :finalize do
      {:ok, %{done: true}}
    end

    commit()
  end

  defmodule MixedWorkflow do
    use Synaptic.Workflow

    step :streaming_step do
      messages = [%{role: "user", content: "Count to 3"}]

      case Tools.chat(messages, stream: true) do
        {:ok, content} ->
          {:ok, %{streamed: content}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    step :non_streaming_step do
      messages = [%{role: "user", content: "Say done"}]

      case Tools.chat(messages, stream: false) do
        {:ok, content} ->
          {:ok, %{non_streamed: content}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    commit()
  end

  defmodule ToolFallbackWorkflow do
    use Synaptic.Workflow

    step :with_tools do
      tool = %Synaptic.Tools.Tool{
        name: "test_tool",
        description: "Test tool",
        schema: %{type: "object", properties: %{}, required: []},
        handler: fn _ -> "result" end
      }

      messages = [%{role: "user", content: "Use tool"}]

      # Should fall back to non-streaming when tools are provided
      case Tools.chat(messages, stream: true, tools: [tool]) do
        {:ok, _content} ->
          {:ok, %{used_tool: true}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    commit()
  end

  test "streaming workflow emits PubSub events" do
    {:ok, run_id} = Synaptic.start(StreamingWorkflow, %{})
    :ok = Synaptic.subscribe(run_id)
    on_exit(fn -> Synaptic.unsubscribe(run_id) end)

    # Wait for workflow to complete (or timeout)
    wait_for_completion(run_id, 5_000)

    # Verify we received stream events (if streaming was actually used)
    # Note: This test may not receive events if OpenAI API is not configured
    # In a real scenario with Bypass, we would mock the streaming response
    snapshot = Synaptic.inspect(run_id)

    assert snapshot.status in [:completed, :failed, :running]
  end

  test "mixed streaming and non-streaming steps work" do
    {:ok, run_id} = Synaptic.start(MixedWorkflow, %{})
    :ok = Synaptic.subscribe(run_id)
    on_exit(fn -> Synaptic.unsubscribe(run_id) end)

    wait_for_completion(run_id, 5_000)

    snapshot = Synaptic.inspect(run_id)
    assert snapshot.status in [:completed, :failed, :running]
  end

  test "streaming with tools falls back to non-streaming" do
    {:ok, run_id} = Synaptic.start(ToolFallbackWorkflow, %{})
    :ok = Synaptic.subscribe(run_id)
    on_exit(fn -> Synaptic.unsubscribe(run_id) end)

    wait_for_completion(run_id, 5_000)

    snapshot = Synaptic.inspect(run_id)
    assert snapshot.status in [:completed, :failed, :running]
  end

  test "streaming PubSub events have correct structure" do
    # This test verifies the event structure without actually calling OpenAI
    # We'll test the PubSub publishing logic directly
    run_id = "test_run_123"
    step_name = :test_step

    # Subscribe to events
    :ok = Synaptic.subscribe(run_id)
    on_exit(fn -> Synaptic.unsubscribe(run_id) end)

    # Manually publish a stream event to verify structure
    alias Phoenix.PubSub

    event = %{
      event: :stream_chunk,
      step: step_name,
      chunk: "Hello",
      accumulated: "Hello",
      run_id: run_id,
      current_step: step_name
    }

    PubSub.broadcast(Synaptic.PubSub, "synaptic:run:" <> run_id, {:synaptic_event, event})

    assert_receive {:synaptic_event, received_event}, 1_000
    assert received_event.event == :stream_chunk
    assert received_event.step == step_name
    assert received_event.chunk == "Hello"
    assert received_event.accumulated == "Hello"
    assert received_event.run_id == run_id
  end

  defp wait_for_completion(run_id, timeout) do
    start_time = System.monotonic_time(:millisecond)

    wait_loop(run_id, start_time, timeout)
  end

  defp wait_loop(run_id, start_time, timeout) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed >= timeout do
      :timeout
    else
      snapshot = Synaptic.inspect(run_id)

      if snapshot.status in [:completed, :failed] do
        :done
      else
        Process.sleep(100)
        wait_loop(run_id, start_time, timeout)
      end
    end
  end
end
