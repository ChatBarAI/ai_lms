require "test_helper"

class AiModelConfigurationTest < ActiveSupport::TestCase
  test "accepts the official host for the selected provider" do
    configuration = AiModelConfiguration.new(
      name: "OpenAI", provider: "openai", model: "gpt-5.1",
      base_url: "https://api.openai.com/v1"
    )

    assert configuration.valid?
  end

  test "rejects private and unapproved provider hosts" do
    configuration = AiModelConfiguration.new(
      name: "Internal", provider: "openai", model: "gpt-5.1",
      base_url: "https://127.0.0.1/v1"
    )

    assert_not configuration.valid?
    assert_includes configuration.errors[:base_url], "must use an approved HTTPS provider host"
  end

  test "rejects credentials embedded in a provider URL" do
    configuration = AiModelConfiguration.new(
      name: "Unsafe", provider: "openai", model: "gpt-5.1",
      base_url: "https://user:password@api.openai.com/v1"
    )

    assert_not configuration.valid?
  end
end
