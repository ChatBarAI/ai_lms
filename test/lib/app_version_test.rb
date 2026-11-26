require "test_helper"

class AppVersionTest < ActiveSupport::TestCase
  SHA = "157b437a1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f".freeze

  setup { AppVersion.reset! }
  teardown { AppVersion.reset! }

  test "prefers the REVISION file written by bin/deploy" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "REVISION"), "#{SHA}\n")
      assert_equal SHA, AppVersion.detect_revision(root: Pathname(dir), env: { "APP_REVISION" => "other" })
    end
  end

  test "falls back to APP_REVISION and then unknown" do
    Dir.mktmpdir do |dir|
      assert_equal SHA, AppVersion.detect_revision(root: Pathname(dir), env: { "APP_REVISION" => " #{SHA} " })
      assert_equal "unknown", AppVersion.detect_revision(root: Pathname(dir), env: {})
    end
  end

  test "builds GitHub history and compare links from a clean revision" do
    AppVersion.instance_variable_set(:@revision, SHA)

    assert_equal "157b437", AppVersion.label
    assert_not AppVersion.dirty?
    assert_equal "https://github.com/ChatBarAI/ai_lms/commits/#{SHA}", AppVersion.history_url
    assert_equal "https://github.com/ChatBarAI/ai_lms/compare/#{SHA}...main", AppVersion.whats_new_url
  end

  test "flags --dirty deploy releases but still links the base commit" do
    AppVersion.instance_variable_set(:@revision, "#{SHA}-dirty-20261126120000")

    assert AppVersion.dirty?
    assert_equal "157b437-dirty", AppVersion.label
    assert_equal "https://github.com/ChatBarAI/ai_lms/commits/#{SHA}", AppVersion.history_url
  end

  test "has no link when the revision is unknown" do
    AppVersion.instance_variable_set(:@revision, "unknown")

    assert_nil AppVersion.history_url
    assert_nil AppVersion.whats_new_url
    assert_equal "unknown", AppVersion.label
  end

  test "copyright matches the LICENSE file" do
    holder = AppVersion::COPYRIGHT.delete_prefix("© ")
    assert_includes Rails.root.join("LICENSE").read, "Copyright (c) #{holder}"
  end
end
