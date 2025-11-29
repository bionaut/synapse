import Config

if config_env() == :prod do
  config :synapse, Synapse.Tools.OpenAI,
    api_key: System.fetch_env!("OPENAI_API_KEY"),
    model: System.get_env("OPENAI_MODEL", "gpt-4o-mini")
end
