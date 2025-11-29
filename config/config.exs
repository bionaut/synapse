import Config

# Synapse workflow defaults
config :synapse, Synapse.Tools, llm_adapter: Synapse.Tools.OpenAI

config :synapse, Synapse.Tools.OpenAI,
  finch: Synapse.Finch,
  model: "gpt-4o-mini"

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: []

import_config "#{config_env()}.exs"
