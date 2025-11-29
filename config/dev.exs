import Config

config :synaptic, Synaptic.Tools.OpenAI,
  api_key: System.get_env("OPENAI_API_KEY"),
  model: "gpt-4o-mini"

config :logger, :console, format: "[$level] $message\n"
