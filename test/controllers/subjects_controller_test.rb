require "test_helper"

class SubjectsControllerTest < ActionDispatch::IntegrationTest
  test "index is accessible anonymously" do
    get subjects_path
    assert_response :success
  end

  test "show by slug works" do
    get subject_path(subjects(:math))
    assert_response :success
    assert_match(/Algebra/, response.body)
  end

  test "show only lists published courses" do
    get subject_path(subjects(:math))
    assert_no_match(/Draft Course/, response.body)
  end
end
