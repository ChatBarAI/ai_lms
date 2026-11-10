require "test_helper"

class ChatbarNamesControllerTest < ActionDispatch::IntegrationTest
  test "instructor can look up an unsaved key without modifying lessons" do
    sign_in users(:instructor)
    before = lessons(:intro).attributes
    client = Struct.new(:details).new({ "business_name" => "New tutor", "token" => "private-token" })

    CbaiClient.stub(:new, ->(api_key:) { assert_equal "new-key", api_key; client }) do
      assert_no_difference("Lesson.count") do
        post course_chatbar_name_path(courses(:algebra)), params: { api_key: "new-key" }, as: :json
      end
    end

    assert_response :success
    assert_equal({ "name" => "New tutor" }, response.parsed_body)
    assert_equal before, lessons(:intro).reload.attributes
  end

  test "students cannot look up names" do
    sign_in users(:student)
    CbaiClient.stub(:new, ->(**) { flunk "must authorize before contacting ChatBar" }) do
      post course_chatbar_name_path(courses(:algebra)), params: { api_key: "key" }, as: :json
    end
    assert_response :forbidden
  end

  test "anonymous visitors cannot look up names" do
    CbaiClient.stub(:new, ->(**) { flunk "must authenticate before contacting ChatBar" }) do
      post course_chatbar_name_path(courses(:algebra)), params: { api_key: "key" }, as: :json
    end
    assert_response :unauthorized
  end

  test "lookup errors do not expose upstream details" do
    sign_in users(:instructor)
    CbaiClient.stub(:new, ->(**) { raise CbaiClient::Error, "private upstream response" }) do
      post course_chatbar_name_path(courses(:algebra)), params: { api_key: "key" }, as: :json
    end
    assert_response :unprocessable_entity
    assert_not_includes response.body, "private upstream response"
  end
end
