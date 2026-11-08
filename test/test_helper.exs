Code.require_file("support/fixtures.ex", __DIR__)
Code.require_file("support/echo_handler.ex", __DIR__)

{:ok, _} = Application.ensure_all_started(:phoenix_pubsub)
{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: A2aEngine.TestPubSub)

ExUnit.start()
