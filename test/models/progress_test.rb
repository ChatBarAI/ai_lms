require "test_helper"

class ProgressTest < ActiveSupport::TestCase
  test "fixture is valid" do
    assert progresses(:student_intro).valid?
  end

  test "score numericality bounds" do
    p = progresses(:student_intro)
    p.score = -1
    assert_not p.valid?
    p.score = 101
    assert_not p.valid?
    p.score = 50
    assert p.valid?
  end

  test "enrollment+lesson uniqueness" do
    dup = Progress.new(enrollment: enrollments(:student_in_algebra), lesson: lessons(:intro))
    assert_not dup.valid?
  end

  test "stamps completed_at on transition to completed" do
    p = progresses(:student_intro)
    assert_nil p.completed_at
    p.status = :completed
    p.save!
    assert_not_nil p.reload.completed_at
  end

  test "does not overwrite an existing completed_at" do
    p = progresses(:student_intro)
    earlier = 1.year.ago
    p.update!(status: :completed, completed_at: earlier)
    p.update!(score: 90)
    assert_in_delta earlier.to_f, p.reload.completed_at.to_f, 1.0
  end
end
