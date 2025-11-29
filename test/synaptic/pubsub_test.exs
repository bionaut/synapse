defmodule Synaptic.PubSubTest do
  use ExUnit.Case

  defmodule QuestionsWorkflow do
    use Synaptic.Workflow

    step :pause, suspend: true, resume_schema: %{answer: :boolean} do
      case get_in(context, [:human_input, :answer]) do
        nil -> suspend_for_human("Need answer")
        answer -> {:ok, %{answer: answer}}
      end
    end

    step :finish do
      {:ok, %{done: true}}
    end

    commit()
  end

  test "publishes events for a workflow run" do
    {:ok, run_id} = Synaptic.start(QuestionsWorkflow, %{})
    :ok = Synaptic.subscribe(run_id)
    drain_events()

    :ok = Synaptic.resume(run_id, %{answer: true})

    assert_receive {:synaptic_event, %{event: :resumed, run_id: ^run_id}}, 1_000

    assert_receive {:synaptic_event, %{event: :step_completed, step: :pause, run_id: ^run_id}},
                   1_000

    assert_receive {:synaptic_event, %{event: :step_completed, step: :finish, run_id: ^run_id}},
                   1_000

    assert_receive {:synaptic_event, %{event: :completed, run_id: ^run_id}}, 1_000

    Synaptic.unsubscribe(run_id)
  end

  defp drain_events do
    receive do
      {:synaptic_event, _} -> drain_events()
    after
      50 -> :ok
    end
  end
end
