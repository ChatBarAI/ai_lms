require "test_helper"

class AbilityTest < ActiveSupport::TestCase
  def ability_for(user)
    Ability.new(user)
  end

  test "anonymous can read public published catalogue" do
    a = ability_for(nil)
    assert a.can?(:read, subjects(:math))
    assert a.can?(:read, courses(:algebra))
    assert_not a.can?(:read, courses(:other_owner_course))
    assert_not a.can?(:read, courses(:draft_course))
    assert a.can?(:read, lessons(:intro))
    assert_not a.can?(:read, lessons(:physics_lesson))
    assert_not a.can?(:read, lessons(:draft_lesson))
  end

  test "anonymous cannot read catalogue when guest access is disabled" do
    SiteSetting.current.update!(allow_guest_access: false)
    a = ability_for(nil)
    assert_not a.can?(:read, subjects(:math))
    assert_not a.can?(:read, courses(:algebra))
    assert_not a.can?(:read, lessons(:intro))
  ensure
    SiteSetting.current.update!(allow_guest_access: true)
  end

  test "authenticated user can still read catalogue when guest access is disabled" do
    SiteSetting.current.update!(allow_guest_access: false)
    a = ability_for(users(:student))
    assert a.can?(:read, courses(:algebra))
    assert a.can?(:read, courses(:other_owner_course))
  ensure
    SiteSetting.current.update!(allow_guest_access: true)
  end

  test "admin can manage everything" do
    a = ability_for(users(:admin))
    assert a.can?(:manage, Course)
    assert a.can?(:destroy, courses(:algebra))
    assert a.can?(:manage, lessons(:draft_lesson))
  end

  test "instructor can manage own course's lessons but not others'" do
    a = ability_for(users(:instructor))
    assert a.can?(:manage, lessons(:intro))
    assert a.can?(:manage, lessons(:draft_lesson))
    assert_not a.can?(:manage, lessons(:physics_lesson))
    assert a.can?(:update, courses(:algebra))
    assert_not a.can?(:update, courses(:other_owner_course))
  end

  test "students manage their own ratings only" do
    a = ability_for(users(:student))
    own = ratings(:student_intro_rating)
    other = Rating.new(user: users(:other_student), lesson: lessons(:intro), stars: 3)
    assert a.can?(:update, own)
    assert_not a.can?(:update, other)
  end

  test "student can read own drafts of nothing but can read published lessons" do
    a = ability_for(users(:student))
    assert a.can?(:read, lessons(:intro))
    assert_not a.can?(:read, lessons(:draft_lesson))
  end

  test "student cannot read questions from draft lessons" do
    a = ability_for(users(:student))
    draft_question = Question.new(lesson: lessons(:draft_lesson), prompt: "Draft", kind: :multiple_choice)
    assert_not a.can?(:read, draft_question)
  end

  test "student can create their own enrollment" do
    a = ability_for(users(:other_student))
    e = Enrollment.new(user: users(:other_student), course: courses(:algebra))
    assert a.can?(:create, e)
    other = Enrollment.new(user: users(:student), course: courses(:algebra))
    assert_not a.can?(:create, other)
  end
end
