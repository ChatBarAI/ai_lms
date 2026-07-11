require "test_helper"

class VideoClientDownloadSecurityTest < ActiveSupport::TestCase
  test "ChatBar authorization is not forwarded to a cross-host download" do
    client = CbaiClient.new(api_key: "cbai-secret")

    headers = client.send(:download_headers_for, URI("https://dashboard.chatbar-ai.com/video"))
    assert_equal({ "Authorization" => "cbai-secret" }, headers)
    assert_empty client.send(:download_headers_for, URI("https://storage.example/video"))
  end

  test "Synthesia authorization is not forwarded to a cross-host download" do
    client = SynthesiaClient.new(api_key: "synthesia-secret")

    headers = client.send(:download_headers_for, URI("https://api.synthesia.io/video"))
    assert_equal({ "Authorization" => "synthesia-secret" }, headers)
    assert_empty client.send(:download_headers_for, URI("https://storage.example/video"))
  end

  test "HeyGen authorization is not forwarded to a cross-host download" do
    client = HeygenClient.new(api_key: "heygen-secret")

    headers = client.send(:download_headers_for, URI("https://files.heygen.com/video"))
    assert_equal({ "X-Api-Key" => "heygen-secret" }, headers)
    assert_empty client.send(:download_headers_for, URI("https://storage.example/video"))
  end
end
