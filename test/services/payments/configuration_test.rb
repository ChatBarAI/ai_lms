require "test_helper"

class Payments::ConfigurationTest < ActiveSupport::TestCase
  def base_url_for(url, environment: "development", key: "sk_test_example")
    Rails.stub(:env, ActiveSupport::StringInquirer.new(environment)) do
      SiteSetting.stub(:current, Struct.new(:app_url).new(url)) do
        Payments::Configuration.stub(:secret, key) do
          Payments::Configuration.base_url
        end
      end
    end
  end

  test "development test keys allow HTTP loopback origins" do
    %w[localhost 127.0.0.1 [::1]].each do |host|
      %w[sk_test_example rk_test_example].each do |key|
        url = "http://#{host}:3000"
        assert_equal url, base_url_for("#{url}/", key: key)
      end
    end
  end

  test "HTTP exception requires development and a test key" do
    %w[production staging test].each do |environment|
      assert_raises(Payments::Error) { base_url_for("http://localhost:3000", environment: environment) }
    end
    [nil, "", "sk_live_example", "rk_live_example"].each do |key|
      assert_raises(Payments::Error) { base_url_for("http://localhost:3000", key: key) }
    end
  end

  test "local development exception still rejects nonlocal hosts and non-origin URLs" do
    %w[http://example.com http://localhost.example.com http://user@localhost:3000 http://localhost:3000/path http://localhost:3000?query=1 http://localhost:3000#fragment].each do |url|
      assert_raises(Payments::Error) { base_url_for(url) }
    end
  end

  test "HTTPS origins remain valid for live production payments" do
    assert_equal "https://lms.example", base_url_for("https://lms.example/", environment: "production", key: "sk_live_example")
  end

  test "secrets are read once per request snapshot and refreshed after a settings save" do
    SiteSetting.current.update!(stripe_secret_key: "sk_test_first")
    Payments::Configuration.reset!
    queries = 0
    counter = ->(*, payload) { queries += 1 if payload[:sql].include?("site_settings") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      5.times { Payments::Configuration.secret("secret_key") }
      Payments::Configuration.livemode?
      Payments::Configuration.secret("account_id")
    end
    assert_equal 1, queries
    SiteSetting.current.update!(stripe_secret_key: "sk_test_second")
    assert_equal "sk_test_second", Payments::Configuration.secret("secret_key")
  end
end
