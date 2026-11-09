require "test_helper"

class LearningCompletionTest < ActionDispatch::IntegrationTest
  setup do
    @course = courses(:algebra)
    @enrollment = enrollments(:student_in_algebra)
    sign_in users(:student)
  end

  test "completed learners see certificate actions on every learner surface without issuing a certificate" do
    @course.lessons_required_for_completion.each do |lesson|
      @enrollment.progresses.find_or_initialize_by(lesson: lesson).update!(status: :completed)
    end

    assert_no_difference "Certificate.count" do
      [ courses_path, course_path(@course), me_path, profile_path,
        course_lesson_path(@course, lessons(:intro)) ].each do |path|
        get path
        assert_response :success
        assert_select "a[href=?]", course_certificate_path(@course)
        assert_select "a[href=?]", course_certificate_path(@course, format: :pdf)
        assert_select "a a", count: 0
      end
    end

    get course_path(@course)
    assert_select "#completion-summary", text: /Time from enrolment to completion:/
    get course_lesson_path(@course, lessons(:intro))
    assert_select "#lesson-status #completion-summary a[href=?]", course_certificate_path(@course)
  end

  test "incomplete learners and guests do not see completion actions" do
    [ courses_path, course_path(@course), me_path, profile_path ].each do |path|
      get path
      assert_response :success
      assert_select "a[href=?]", course_certificate_path(@course), count: 0
      assert_select "#completion-summary", count: 0
    end

    Certificate.find_or_issue(user: users(:student), course: @course)
    sign_out users(:student)
    get courses_path
    assert_select "a[href=?]", course_certificate_path(@course), count: 0
  end

  test "historical certificate availability does not replace current enrolment progress" do
    Certificate.find_or_issue(user: users(:student), course: @course)
    percentage = @enrollment.completion_percentage
    assert_operator percentage, :<, 100

    get me_path

    assert_response :success
    assert_select "[role=progressbar][aria-valuenow=?]", percentage.to_s
    assert_select "span", text: I18n.t("learning_completion.completed"), count: 0
    assert_select "a[href=?]", course_certificate_path(@course)
    assert_select "a[href=?]", course_certificate_path(@course, format: :pdf)
  end

  test "existing certificates remain visible and downloadable without a qualifying enrolment" do
    certificate = Certificate.find_or_issue(user: users(:student), course: @course)
    original_attributes = certificate.attributes
    @enrollment.destroy!

    get course_path(@course)
    assert_select "#completion-summary", text: /completion date is unavailable/
    get profile_path
    assert_select "#my-certificates a[href=?]", course_certificate_path(@course)

    assert_no_difference "Certificate.count" do
      get course_certificate_path(@course)
      assert_response :success
      get course_certificate_path(@course, format: :pdf)
      assert_response :success
      assert_equal "application/pdf", response.media_type
      assert response.body.start_with?("%PDF")
    end
    assert_equal original_attributes, certificate.reload.attributes

    sign_out users(:student)
    sign_in users(:other_student)
    get course_certificate_path(@course)
    assert_redirected_to course_path(@course)
    get profile_path
    assert_select "#my-certificates a[href=?]", course_certificate_path(@course), count: 0
  end
end
