defmodule A2aEngine.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/fosferon/a2a_engine"

  def project do
    [
      app: :a2a_engine,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      test_ignore_filters: [&String.starts_with?(&1, "test/support/")],
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # JSON codec
      {:jason, "~> 1.4"},

      # HTTP server plug (Transport.Http ships a Plug module)
      {:plug, "~> 1.16"},

      # HTTP client (Transport.Http client + TestPeer)
      {:req, "~> 0.7.5"},

      # BEAM-native broadcast bus (Transport.BeamNative + TestPeer signalling)
      {:phoenix_pubsub, "~> 2.1"},

      # Optional: only needed by consumers that use TestPeer (which starts a real
      # server on a random port). Without `only:`, this library's own build has it
      # in every env, including :prod; consumers without TestPeer never pull it in.
      {:bandit, "~> 1.5", optional: true},

      # Property-based tests (test env only)
      {:stream_data, "~> 1.1", only: [:dev, :test]},

      # Documentation
      {:ex_doc, "~> 0.36", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Pure-spec implementation of the Google Agent2Agent (A2A) protocol:
    types, JSON-RPC 2.0 codec, SSE codec, and transport behaviour. No
    state, no DB, no broker — those live in the consuming host.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "A2A spec" => "https://a2a-protocol.org/"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "LICENSE", "CHANGELOG.md"],
      groups_for_modules: [
        Types: [
          A2aEngine.Types.AgentCapabilities,
          A2aEngine.Types.AgentCard,
          A2aEngine.Types.AgentExtension,
          A2aEngine.Types.AgentInterface,
          A2aEngine.Types.AgentProvider,
          A2aEngine.Types.AgentSkill,
          A2aEngine.Types.Artifact,
          A2aEngine.Types.DataPart,
          A2aEngine.Types.FilePart,
          A2aEngine.Types.FileWithBytes,
          A2aEngine.Types.FileWithUri,
          A2aEngine.Types.Message,
          A2aEngine.Types.MessageSendConfiguration,
          A2aEngine.Types.MessageSendParams,
          A2aEngine.Types.Part,
          A2aEngine.Types.PushNotificationAuthenticationInfo,
          A2aEngine.Types.PushNotificationConfig,
          A2aEngine.Types.Task,
          A2aEngine.Types.TaskArtifactUpdateEvent,
          A2aEngine.Types.TaskIdParams,
          A2aEngine.Types.TaskPushNotificationConfig,
          A2aEngine.Types.TaskQueryParams,
          A2aEngine.Types.TaskStatus,
          A2aEngine.Types.TaskStatusUpdateEvent,
          A2aEngine.Types.TextPart
        ],
        Codec: [
          A2aEngine.Codec.JsonRpc,
          A2aEngine.Codec.Keys,
          A2aEngine.Codec.SSE
        ],
        Transport: [
          A2aEngine.Transport,
          A2aEngine.Transport.Http,
          A2aEngine.Transport.Http.Plug,
          A2aEngine.Transport.BeamNative,
          A2aEngine.Transport.BeamNative.Server
        ],
        Auth: [
          A2aEngine.Auth,
          A2aEngine.Auth.Bearer,
          A2aEngine.Auth.Localhost
        ],
        "Core & Helpers": [
          A2aEngine,
          A2aEngine.Handler,
          A2aEngine.Errors,
          A2aEngine.LifecycleState,
          A2aEngine.Parts,
          A2aEngine.TestPeer,
          A2aEngine.TestPeer.Handler
        ]
      ]
    ]
  end
end
