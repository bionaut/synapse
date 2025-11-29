defmodule Synaptic.RuntimeSupervisor do
  @moduledoc """
  DynamicSupervisor responsible for spinning up `Synaptic.Runner` processes.
  """

  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
