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

  test "show filters courses by signed in user's course languages" do
    courses(:algebra).update!(locale: "en")
    student = users(:student)
    student.update!(course_locales: [ "de" ])
    sign_in student

    get subject_path(subjects(:math))

    assert_response :success
    assert_no_match(/Algebra/, response.body)
  end

  test "show course card images keep the 728x320 upload shape" do
    courses(:algebra).cover_image.attach(io: file_fixture("poster.png").open, filename: "cover.png", content_type: "image/png")

    get subject_path(subjects(:math))

    assert_response :success
    assert_select "img[class~=?]", "aspect-[728/320]"
    assert_select "img[class~=h-40]", count: 0
  end
end
