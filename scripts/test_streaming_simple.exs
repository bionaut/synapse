# Simple streaming test - no interactive prompts
# Usage: MIX_ENV=dev mix run scripts/test_streaming_simple.exs [topic]

alias Synaptic.Dev.DemoWorkflow

topic = case System.argv() do
  [t | _] -> t
  _ -> "Elixir Pattern Matching"
end

IO.puts("🚀 Testing streaming with topic: #{topic}\n")

# Skip directly to streaming step
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

{:ok, run_id} = Synaptic.start(DemoWorkflow, context, start_at_step: :generate_learning_plan)
:ok = Synaptic.subscribe(run_id)

IO.puts("✓ Started workflow: #{run_id}\n")
IO.puts("📡 Streaming output:\n")
IO.puts(String.duplicate("─", 60))

# Collect all events
receive_loop = fn ->
  receive do
    {:synaptic_event, %{event: :stream_chunk, chunk: chunk}} ->
      IO.write(chunk)
      receive_loop.()

    {:synaptic_event, %{event: :stream_done, accumulated: full}} ->
      IO.puts("\n" <> String.duplicate("─", 60))
      IO.puts("\n✓ Streaming complete!\n")
      IO.puts("Full content:\n")
      IO.puts(full)
      :done

    {:synaptic_event, %{event: :completed}} ->
      IO.puts("\n✓ Workflow completed")
      :done

    {:synaptic_event, %{event: :failed, reason: reason}} ->
      IO.puts("\n❌ Failed: #{inspect(reason)}")
      :done

    {:synaptic_event, _} = event ->
      # Ignore other events for simplicity
      receive_loop.()
  after
    60_000 ->
      IO.puts("\n⏱️  Timeout")
      :timeout
  end
end

case receive_loop.() do
  :done ->
    Synaptic.unsubscribe(run_id)
    IO.puts("\n✅ Test complete!\n")

  :timeout ->
    Synaptic.unsubscribe(run_id)
    IO.puts("\n⚠️  Test timed out\n")
end
