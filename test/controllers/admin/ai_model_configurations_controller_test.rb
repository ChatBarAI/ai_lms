require "test_helper"

class Admin::AiModelConfigurationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "admin can list and edit a configuration encrypted by another application" do
    configuration = unreadable_configuration

    get admin_ai_model_configurations_path
    assert_response :success
    assert_includes response.body, "API key cannot be decrypted"

    get edit_admin_ai_model_configuration_path(configuration)
    assert_response :success
    assert_includes response.body, "The saved AI provider API key cannot be decrypted"
    assert_select "input[name='ai_model_configuration[api_key]'][value]", count: 0
  end

  test "admin can replace an unreadable API key using local encryption" do
    configuration = unreadable_configuration

    patch admin_ai_model_configuration_path(configuration), params: {
      ai_model_configuration: { api_key: "replacement-key", name: "Local model" }
    }

    assert_redirected_to admin_ai_model_configurations_path
    configuration.reload
    assert_equal "replacement-key", configuration.api_key
    assert_equal :configured, configuration.api_key_status
    assert_equal "Local model", configuration.name
    assert_not_includes configuration.api_key_before_type_cast, "replacement-key"
  end

  test "invalid replacement preserves the original ciphertext" do
    configuration = unreadable_configuration
    ciphertext = configuration.api_key_before_type_cast

    patch admin_ai_model_configuration_path(configuration), params: {
      ai_model_configuration: { api_key: "replacement-key", name: "" }
    }

    assert_response :unprocessable_entity
    configuration.reload
    assert_equal ciphertext, configuration.api_key_before_type_cast
    assert_equal :unreadable, configuration.api_key_status
    assert_equal "Imported model", configuration.name
  end

  test "blank replacement preserves an unreadable API key" do
    configuration = unreadable_configuration
    ciphertext = configuration.api_key_before_type_cast

    patch admin_ai_model_configuration_path(configuration), params: {
      ai_model_configuration: { api_key: "", name: "Renamed model" }
    }

    assert_redirected_to admin_ai_model_configurations_path
    configuration.reload
    assert_equal ciphertext, configuration.api_key_before_type_cast
    assert_equal :unreadable, configuration.api_key_status
    assert_equal "Renamed model", configuration.name
  end

  test "blank replacement preserves a readable API key" do
    configuration = AiModelConfiguration.create!(
      name: "Local model", provider: "openai", model: "test-model",
      base_url: "https://api.openai.com/v1", api_key: "existing-key"
    )

    patch admin_ai_model_configuration_path(configuration), params: {
      ai_model_configuration: { api_key: "", name: "Renamed model" }
    }

    assert_redirected_to admin_ai_model_configurations_path
    assert_equal "existing-key", configuration.reload.api_key
    assert_equal "Renamed model", configuration.name
  end

  private

  def unreadable_configuration
    other_key_provider = ActiveRecord::Encryption::DerivedSecretKeyProvider.new("another-application-secret")
    configuration = ActiveRecord::Encryption.with_encryption_context(key_provider: other_key_provider) do
      AiModelConfiguration.create!(
        name: "Imported model", provider: "openai", model: "test-model",
        base_url: "https://api.openai.com/v1", api_key: "original-key"
      )
    end
    configuration.reload
    assert_equal :unreadable, configuration.api_key_status
    configuration
  end
end
