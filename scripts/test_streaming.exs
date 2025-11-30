# Test script for Synaptic workflow streaming functionality
#
# Usage:
#   mix run scripts/test_streaming.exs [topic]
#   mix run scripts/test_streaming.exs "Elixir Concurrency"
#
# Or load in IEx:
#   Code.require_file("scripts/test_streaming.exs")
#   TestStreaming.run()

defmodule TestStreaming do
  @moduledoc """
  Interactive test script for Synaptic workflow streaming.
  """

  alias Synaptic.Dev.DemoWorkflow

  def run(topic \\ "Elixir Pattern Matching") do
    IO.puts("""
    ╔══════════════════════════════════════════════════════════════╗
    ║  Synaptic Workflow Streaming Test                           ║
    ╚══════════════════════════════════════════════════════════════╝
    """)

    IO.puts("📚 Topic: #{topic}\n")

    # Option 1: Start from beginning (will prompt for questions)
    # Option 2: Skip directly to streaming step

    IO.puts("Choose test mode:")
    IO.puts("1. Full workflow (with questions)")
    IO.puts("2. Skip to streaming step (no questions)")
    IO.write("Enter choice [1]: ")

    choice =
      case IO.gets("") |> String.trim() do
        "2" -> :skip_to_streaming
        _ -> :full
      end

    IO.puts("\n")

    {run_id, context} =
      case choice do
        :full ->
          IO.puts("🚀 Starting full workflow...\n")
          {:ok, run_id} = Synaptic.start(DemoWorkflow, %{topic: topic})
          {run_id, nil}

        :skip_to_streaming ->
          IO.puts("🚀 Starting at streaming step...\n")
          context = %{
            topic: topic,
            clarification_answers: %{
              "q_background" => "I'm a beginner",
              "q_goal" => "Learn the fundamentals"
            },
            pending_questions: [],
            current_question: nil,
            question_source: :fallback
          }

          {:ok, run_id} =
            Synaptic.start(DemoWorkflow, context, start_at_step: :generate_learning_plan)

          {run_id, context}
      end

    IO.puts("✓ Workflow started with run_id: #{run_id}\n")

    # Subscribe to events
    :ok = Synaptic.subscribe(run_id)
    IO.puts("✓ Subscribed to events\n")

    # Start event handler
    handle_events(run_id, choice)
  end

  defp handle_events(run_id, choice) do
    receive do
      {:synaptic_event, %{event: :stream_chunk, chunk: chunk, step: step}} ->
        IO.write(chunk)
        handle_events(run_id, choice)

      {:synaptic_event, %{event: :stream_done, accumulated: full, step: step}} ->
        IO.puts("\n\n" <> String.duplicate("─", 60))
        IO.puts("✓ [#{step}] Streaming complete!")
        IO.puts(String.duplicate("─", 60))
        IO.puts("\nFull content:\n")
        IO.puts(full)
        IO.puts("\n" <> String.duplicate("─", 60) <> "\n")
        handle_events(run_id, choice)

      {:synaptic_event, %{event: :waiting_for_human, message: msg, step: step}} ->
        IO.puts("\n" <> String.duplicate("─", 60))
        IO.puts("⏸️  [#{step}] Waiting for human input")
        IO.puts("Message: #{msg}")
        IO.puts(String.duplicate("─", 60))

        snapshot = Synaptic.inspect(run_id)
        if snapshot.waiting do
          IO.inspect(snapshot.waiting, label: "Waiting details", pretty: true)
        end

        # Auto-resume with sample answers for demo
        if choice == :full do
          IO.puts("\n💡 Auto-answering for demo...")
          answer = case step do
            :ask_questions -> "I'm a beginner"
            :human_review -> true
            _ -> "Sample answer"
          end

          resume_payload =
            if step == :human_review do
              %{approved: answer}
            else
              %{answer: answer}
            end

          IO.puts("Resuming with: #{inspect(resume_payload)}")
          Synaptic.resume(run_id, resume_payload)
          IO.puts("✓ Resumed\n")
        end

        handle_events(run_id, choice)

      {:synaptic_event, %{event: :step_completed, step: step}} ->
        IO.puts("\n✓ [#{step}] Step completed")
        handle_events(run_id, choice)

      {:synaptic_event, %{event: :completed}} ->
        IO.puts("\n" <> String.duplicate("═", 60))
        IO.puts("🎉 Workflow completed successfully!")
        IO.puts(String.duplicate("═", 60))

        snapshot = Synaptic.inspect(run_id)
        IO.puts("\nFinal context keys: #{inspect(Map.keys(snapshot.context))}")

        if Map.has_key?(snapshot.context, :outline) do
          IO.puts("\nGenerated outline:")
          IO.puts(String.duplicate("─", 60))
          IO.puts(snapshot.context.outline)
          IO.puts(String.duplicate("─", 60))
        end

        history = Synaptic.history(run_id)
        IO.puts("\nExecution history (#{length(history)} events):")
        Enum.each(history, fn entry ->
          step = Map.get(entry, :step, "N/A")
          event = Map.get(entry, :event, Map.get(entry, :status, "N/A"))
          IO.puts("  - [#{step}] #{event}")
        end)

        cleanup(run_id)
        :done

      {:synaptic_event, %{event: :failed, reason: reason}} ->
        IO.puts("\n❌ Workflow failed: #{inspect(reason)}")
        cleanup(run_id)
        :done

      {:synaptic_event, %{event: event} = payload} ->
        IO.puts("\n📢 Event: #{event}")
        IO.inspect(payload, label: "Payload", pretty: true, limit: :infinity)
        handle_events(run_id, choice)
    after
      120_000 ->
        IO.puts("\n⏱️  Timeout waiting for events")
        snapshot = Synaptic.inspect(run_id)
        IO.inspect(snapshot, label: "Current state", pretty: true)
        cleanup(run_id)
        :timeout
    end
  end

  defp cleanup(run_id) do
    Synaptic.unsubscribe(run_id)
    IO.puts("\n✓ Cleaned up subscriptions")
    IO.puts("\nTest complete! 🎉\n")
  end
end

# If run directly (not loaded in IEx), execute immediately
if Code.ensure_loaded?(Mix) and Mix.env() == :dev do
  topic = case System.argv() do
    [t | _] -> t
    _ -> "Elixir Pattern Matching"
  end

  # Run in the current process
  TestStreaming.run(topic)
end
