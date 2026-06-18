require "test_helper"

class CbaiClientTest < ActiveSupport::TestCase
  test "constructor rejects blank api key" do
    assert_raises(CbaiClient::Error) { CbaiClient.new(api_key: "") }
    assert_raises(CbaiClient::Error) { CbaiClient.new(api_key: nil) }
    assert_raises(CbaiClient::Error) { CbaiClient.new(api_key: "   ") }
  end

  test "build_uri accepts the default allowlisted host" do
    client = CbaiClient.new(api_key: "key")
    uri = client.send(:build_uri, "/api/cbai/recordings")
    assert_equal "dashboard.chatbar-ai.com", uri.host
    assert_equal "/api/cbai/recordings", uri.path
  end

  test "build_uri accepts overridden base_url for local testing" do
    # Override is permitted intentionally so dev/test can target a local server.
    client = CbaiClient.new(api_key: "key", base_url: "http://localhost:9999")
    uri = client.send(:build_uri, "/api/cbai/recordings")
    assert_equal "localhost", uri.host
  end

  test "details parses json response" do
    client = CbaiClient.new(api_key: "key")

    client.stub(:get, '{"token":"tok_details","name":"Demo"}') do
      details = client.details
      assert_equal "tok_details", details["token"]
      assert_equal "Demo", details["name"]
    end
  end

  test "create_task uses the recordings base URL" do
    client = CbaiClient.new(api_key: "key")
    uri = client.send(:build_uri, "/api/cbai/tasks")
    assert_equal "dashboard.chatbar-ai.com", uri.host
    assert_equal "/api/cbai/tasks", uri.path
  end

  test "create_task posts and parses response" do
    client = CbaiClient.new(api_key: "key")
    client.stub(:post_json, '{"id":12345,"status":"launched"}') do
      response = client.create_task(payload: { name: "n" })
      assert_equal 12345, response["id"]
      assert_equal "launched", response["status"]
    end
  end

  test "score_answer returns integer 1..10 from query response" do
    client = CbaiClient.new(api_key: "key")
    stub_body = '{"answer":"7","search_results":[]}'
    client.stub(:post_json, stub_body) do
      score = client.score_answer(question: "Who?", student_answer: "Bob", expected_answer: "Alice")
      assert_equal 7, score
    end
  end

  test "score_answer raises on out-of-range answer" do
    client = CbaiClient.new(api_key: "key")
    stub_body = '{"answer":"99","search_results":[]}'
    client.stub(:post_json, stub_body) do
      assert_raises(CbaiClient::Error) do
        client.score_answer(question: "Q", student_answer: "A", expected_answer: "E")
      end
    end
  end

  test "score_answer raises on non-numeric answer" do
    client = CbaiClient.new(api_key: "key")
    stub_body = '{"answer":"great job!","search_results":[]}'
    client.stub(:post_json, stub_body) do
      assert_raises(CbaiClient::Error) do
        client.score_answer(question: "Q", student_answer: "A", expected_answer: "E")
      end
    end
  end
end
