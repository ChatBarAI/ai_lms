require "test_helper"

class ProgressesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:student)
    @progress = progresses(:student_intro)
    sign_in @user
  end

  test "student cannot forge quiz completion" do
    assert_no_changes -> { @progress.reload.status } do
      patch progress_path(@progress), params: { progress: { status: "completed" } }
    end

    assert_redirected_to root_path
    assert_equal "in_progress", @progress.reload.status
  end

  test "student cannot forge a score" do
    assert_no_changes -> { @progress.reload.attributes.slice("status", "score") } do
      patch progress_path(@progress), params: {
        progress: { status: "completed", score: 100 }
      }
    end

    assert_redirected_to root_path
    assert_nil @progress.reload.score
  end

  test "student can manually complete a content-only lesson" do
    lesson = courses(:algebra).lessons.create!(
      title: "Content only",
      position: 99,
      published_at: Time.current
    )
    progress = @user.enrollments.find_by!(course: courses(:algebra)).progresses.create!(lesson: lesson)

    patch progress_path(progress), params: { progress: { status: "completed" } }

    assert_redirected_to root_path
    assert progress.reload.completed?
    assert_nil progress.score
  end
end
