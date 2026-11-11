require "test_helper"

class Admin::StripeSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @settings = SiteSetting.current
    @settings.update!(stripe_secret_key: "sk_test_stored", stripe_webhook_secret: "whsec_stored", stripe_account_id: "acct_stored")
  end

  test "credential fields never redisplay saved secrets" do
    sign_in users(:admin)
    get edit_admin_site_setting_path(section: "payments")
    assert_response :success
    %w[stripe_secret_key stripe_webhook_secret].each do |field|
      assert_select "input[name='site_setting[#{field}]'][type=password][value='']"
      assert_not_includes response.body, @settings.public_send(field)
    end
    assert_select "input[name='site_setting[stripe_account_id]']", count: 0
    assert_not_includes response.body, "translation_missing"
  end

  test "non admins cannot change payment credentials" do
    sign_in users(:instructor)
    patch admin_site_setting_path, params: { section: "payments", site_setting: { stripe_secret_key: "sk_test_attack" } }
    assert_redirected_to root_path
    assert_equal "sk_test_stored", @settings.reload.stripe_secret_key
  end

  test "other settings sections cannot change Stripe credentials" do
    sign_in users(:admin)
    patch admin_site_setting_path, params: { section: "branding", site_setting: { brand_name: "Example", stripe_secret_key: "sk_test_attack" } }
    assert_equal "sk_test_stored", @settings.reload.stripe_secret_key
  end

  test "blank credentials keep existing values" do
    sign_in users(:admin)
    patch admin_site_setting_path, params: { section: "payments", site_setting: { stripe_secret_key: "", stripe_webhook_secret: "", stripe_account_id: "" } }
    assert_redirected_to edit_admin_site_setting_path(anchor: "payments")
    assert_equal "sk_test_stored", @settings.reload.stripe_secret_key
  end

  test "invalid credentials are not echoed in the error form" do
    sign_in users(:admin)
    patch admin_site_setting_path, params: { section: "payments", site_setting: { stripe_secret_key: "invalid-sensitive-value" } }
    assert_response :unprocessable_entity
    assert_not_includes response.body, "invalid-sensitive-value"
    assert_select "input[name='site_setting[stripe_secret_key]'][value='']"
    assert_equal "sk_test_stored", @settings.reload.stripe_secret_key
  end

  test "even an administrator cannot submit the derived account ID" do
    sign_in users(:admin)
    patch admin_site_setting_path, params: { section: "payments", site_setting: { stripe_account_id: "acct_forged" } }
    assert_redirected_to edit_admin_site_setting_path(anchor: "payments")
    assert_equal "acct_stored", @settings.reload.stripe_account_id
  end
end
