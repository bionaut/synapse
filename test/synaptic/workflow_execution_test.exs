defmodule Synaptic.WorkflowExecutionTest do
  use ExUnit.Case

  defmodule ApprovalWorkflow do
    use Synaptic.Workflow

    step :prepare, output: %{prepared: :boolean} do
      {:ok, %{prepared: true}}
    end

    step :human_review,
      suspend: true,
      resume_schema: %{approved: :boolean} do
      case get_in(context, [:human_input, :approved]) do
        nil -> suspend_for_human("Please approve the prepared payload")
        true -> {:ok, %{approval: true}}
        false -> {:error, :rejected}
      end
    end

    step :finalize do
      if Map.get(context, :approval) do
        {:ok, %{status: :approved}}
      else
        {:error, :rejected}
      end
    end

    commit()
  end

  defmodule AlwaysFailWorkflow do
    use Synaptic.Workflow

    step :flaky, retry: 1 do
      {:error, :boom}
    end

    commit()
  end

  test "workflow suspends and resumes" do
    {:ok, run_id} = Synaptic.start(ApprovalWorkflow, %{})

    assert %{status: :waiting_for_human, current_step: :human_review} = Synaptic.inspect(run_id)

    assert :ok = Synaptic.resume(run_id, %{approved: true})
    snapshot = wait_for(run_id, :completed)

    assert snapshot.context[:status] == :approved
    assert List.last(Synaptic.history(run_id))[:event] == :completed
  end

  test "rejects invalid resume payload" do
    {:ok, run_id} = Synaptic.start(ApprovalWorkflow, %{})

    assert {:error, {:missing_fields, [:approved]}} = Synaptic.resume(run_id, %{})
  end

  test "step retries before failing" do
    {:ok, run_id} = Synaptic.start(AlwaysFailWorkflow, %{})
    snapshot = wait_for(run_id, :failed)

    assert snapshot.last_error == :boom
    history = Synaptic.history(run_id)
    assert Enum.count(Enum.filter(history, &(&1[:status] == :error))) >= 1
  end

  test "stop halts a workflow and emits event" do
    {:ok, run_id} = Synaptic.start(ApprovalWorkflow, %{})
    wait_for(run_id, :waiting_for_human)

    :ok = Synaptic.subscribe(run_id)
    on_exit(fn -> Synaptic.unsubscribe(run_id) end)

    assert :ok = Synaptic.stop(run_id, :user_cancelled)

    assert_receive {:synaptic_event,
                    %{event: :stopped, reason: :user_cancelled, run_id: ^run_id}},
                   1_000

    assert {:error, :not_found} = Synaptic.stop(run_id)
  end

  defp wait_for(run_id, status, attempts \\ 20)
  defp wait_for(_run_id, _status, 0), do: flunk("workflow did not reach desired status")

  defp wait_for(run_id, status, attempts) do
    snapshot = Synaptic.inspect(run_id)

    if snapshot.status == status do
      snapshot
    else
      Process.sleep(25)
      wait_for(run_id, status, attempts - 1)
    end
  end
end
