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

  test "content-only progress follows materials and completes without a quiz score" do
    progress = content_progress
    first = add_material(progress.lesson)
    second = add_material(progress.lesson)
    add_material(progress.lesson, required: false)
    assert_equal 0, progress.completion_percentage

    acknowledge(first, progress)
    progress.refresh_material_progress!
    assert progress.in_progress?
    assert_equal 50, progress.completion_percentage

    acknowledge(second, progress)
    progress.refresh_material_progress!
    assert progress.reload.completed?
    assert_equal 100, progress.completion_percentage
    assert_not_nil progress.completed_at
    assert_nil progress.score
    assert_empty progress.quiz_attempts
  end

  test "materials contribute twenty percent when a quiz exists" do
    progress = progresses(:student_intro)
    material = add_material(progress.lesson)
    acknowledge(material, progress)
    progress.refresh_material_progress!

    assert progress.in_progress?
    assert_equal 20, progress.completion_percentage
    progress.update!(score: 50)
    assert_equal 60, progress.completion_percentage
    progress.update!(status: :completed)
    assert_equal 100, progress.completion_percentage
    assert_equal 50, progress.score
  end

  test "quiz-only progress gives the quiz all the weight" do
    progress = progresses(:student_intro)
    progress.update!(score: 40)
    assert_equal 40, progress.completion_percentage
  end

  test "lessons with only optional materials complete after all are acknowledged" do
    progress = content_progress
    material = add_material(progress.lesson, required: false)
    acknowledge(material, progress)
    progress.refresh_material_progress!
    assert progress.completed?
  end

  test "adding a required material keeps credit for optional materials already read" do
    progress = content_progress
    read = add_material(progress.lesson, required: false)
    add_material(progress.lesson, required: false)
    acknowledge(read, progress)
    progress.refresh_material_progress!
    assert_equal 50, progress.completion_percentage

    required = add_material(progress.lesson)
    progress.lesson.lesson_materials.reset
    assert_equal 50, progress.completion_percentage
    assert progress.in_progress?

    acknowledge(required, progress)
    progress.refresh_material_progress!
    assert progress.reload.completed?
  end

  test "optional reading counts alongside required materials but is never needed for completion" do
    progress = content_progress
    required = add_material(progress.lesson)
    optional = add_material(progress.lesson, required: false)

    acknowledge(optional, progress)
    progress.refresh_material_progress!
    assert_equal 50, progress.completion_percentage
    assert progress.in_progress?

    acknowledge(required, progress)
    progress.refresh_material_progress!
    assert progress.reload.completed?
  end

  test "required materials alone complete a lesson that also has unread optional ones" do
    progress = content_progress
    required = add_material(progress.lesson)
    add_material(progress.lesson, required: false)

    acknowledge(required, progress)
    progress.refresh_material_progress!
    assert progress.reload.completed?
  end

  test "empty lessons need explicit completion and other enrollments do not count" do
    progress = content_progress
    progress.refresh_material_progress!
    assert progress.not_started?

    material = add_material(progress.lesson)
    other = Enrollment.create!(user: users(:other_student), course: progress.lesson.course)
    LessonMaterialAcknowledgement.create!(lesson_material: material, enrollment: other)
    progress.refresh_material_progress!
    assert progress.not_started?
    assert_equal 0, progress.completion_percentage
  end

  private

  def content_progress
    lesson = courses(:algebra).lessons.create!(title: "Reading", position: 99, published_at: Time.current)
    enrollments(:student_in_algebra).progresses.create!(lesson: lesson)
  end

  def add_material(lesson, required: true)
    lesson.lesson_materials.create!(title: "Reading", kind: :html, body: "Read this", required: required)
  end

  def acknowledge(material, progress)
    LessonMaterialAcknowledgement.create!(lesson_material: material, enrollment: progress.enrollment)
  end
end
