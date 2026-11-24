require "test_helper"

class CourseSequentialLessonsTest < ActiveSupport::TestCase
  setup do
    @course = courses(:algebra)
    @course.update!(sequential_lessons: true)
    @enrollment = enrollments(:student_in_algebra)
    @intro = lessons(:intro)
    @advanced = lessons(:advanced)
  end

  test "nothing is locked when the course does not require lessons in order" do
    @course.update!(sequential_lessons: false)

    assert_equal({}, @course.locked_lessons_for(@enrollment))
    assert_equal({}, @course.locked_lessons_for(nil))
  end

  test "guests and learners who are not enrolled can open only the first lesson" do
    assert_equal({ @advanced.id => @intro }, @course.locked_lessons_for(nil))
  end

  test "a lesson stays locked until every earlier lesson is complete" do
    assert_equal({ @advanced.id => @intro }, @course.locked_lessons_for(@enrollment))

    progresses(:student_intro).update!(status: :completed)

    assert_equal({}, @course.locked_lessons_for(@enrollment))
  end

  test "draft lessons are not part of the sequence" do
    progresses(:student_intro).update!(status: :completed)
    @enrollment.progresses.create!(lesson: @advanced, status: :completed)

    refute_includes @course.locked_lessons_for(@enrollment).keys, lessons(:draft_lesson).id
  end

  test "a lesson the learner already has progress on is never locked again" do
    @enrollment.progresses.create!(lesson: @advanced, status: :not_started)
    third = @course.lessons.create!(title: "Third", position: 4, published_at: 1.day.ago)

    assert_equal({ third.id => @intro }, @course.locked_lessons_for(@enrollment))
  end

  test "answers waiting for marking count as complete" do
    progresses(:student_intro).update!(status: :completed)
    @enrollment.progresses.create!(lesson: @advanced, status: :in_progress)
    third = @course.lessons.create!(title: "Third", position: 4, published_at: 1.day.ago)

    assert_equal({ third.id => @advanced }, @course.locked_lessons_for(@enrollment))

    QuestionAnswer.find_or_initialize_by(enrollment: @enrollment, question: questions(:intro_q_free))
      .update!(answer_text: "Order does not matter.", ai_score: nil, scored_at: nil)

    assert_equal({}, @course.locked_lessons_for(@enrollment))
  end
end
