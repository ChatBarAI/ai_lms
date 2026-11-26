require "test_helper"

# The running commit is admin-only: self-hosters may treat an exact public
# version as a security risk, so it must never reach anonymous visitors.
class AppRevisionVisibilityTest < ActionDispatch::IntegrationTest
  test "public pages do not expose the running revision" do
    get root_path

    assert_response :success
    assert_no_match "app-revision", response.body
    assert_no_match AppVersion.revision, response.body unless AppVersion.revision == "unknown"
  end
end
