require "test_helper"

class Entitlements::GrantTest < ActiveSupport::TestCase
  setup do
    @user = users(:other_student)
    @course = Course.create!(title: "Paid course", owner: users(:instructor), published_at: 1.day.ago,
      access_policy: "entitlement_required", price_minor: 1000, price_currency: "eur")
  end

  def grant(reference = "test", **options)
    Entitlements::Grant.call(user: @user, course: @course, source: "manual", reference: reference,
      reason: "Support", actor: users(:admin), **options)
  end

  test "replay does not restore revoked grant and independent grants survive" do
    first = grant
    second = grant("second")
    Entitlements::Transition.call(grant: first, action: "revoke", source: "manual", reason: "Withdrawn",
      reference: "withdrawal", actor: users(:admin))
    assert_equal "revoked", grant.reload.status
    assert_equal 2, first.entitlement_events.count
    assert CourseAccess.allowed?(@user, @course)
    assert_equal "active", second.reload.status
  end

  test "effective access observes exact start and expiry boundaries" do
    travel_to Time.current.change(usec: 0) do
      row = grant(expires_at: 1.hour.from_now)
      assert CourseAccess.allowed?(@user, @course)
      travel 1.hour
      assert_not CourseAccess.allowed?(@user, @course)
      row.update!(starts_at: 1.hour.from_now, expires_at: 2.hours.from_now)
      assert_not CourseAccess.allowed?(@user, @course)
    end
  end

  test "only administrators issue manual grants" do
    assert_raises(CanCan::AccessDenied) do
      Entitlements::Grant.call(user: @user, course: @course, source: "manual", reference: "unauthorized",
        reason: "No", actor: users(:instructor))
    end
  end

  test "free to paid conversion grants existing learners and retains progress" do
    course = courses(:algebra)
    enrolled = course.enrollments.pluck(:user_id)
    course.update!(access_policy: "entitlement_required", price_minor: 500, price_currency: "eur")
    assert_equal enrolled.sort, course.course_entitlements.effective.pluck(:user_id).sort
    assert_equal enrolled.length, EntitlementEvent.where(reason: "free_to_paid").count
  end

  test "a grant never publishes a draft" do
    grant
    lesson = @course.lessons.create!(title: "Locked", position: 1, published_at: Time.current)
    assert Ability.new(@user).can?(:read, lesson)
    @course.update!(published_at: nil)
    assert_not Ability.new(@user).can?(:read, lesson.reload)
  end

  test "an enrolment alone cannot authorize paid learning" do
    assert_not Enrollment.new(user: @user, course: @course).valid?
    lesson = @course.lessons.create!(title: "Private", position: 1, published_at: Time.current)
    assert_not Ability.new(@user).can?(:read, lesson)
    assert_not Lesson.accessible_by(Ability.new(@user)).exists?(lesson.id)
    grant
    assert Ability.new(@user).can?(:read, lesson)
    assert Lesson.accessible_by(Ability.new(@user)).exists?(lesson.id)
  end

  test "retained grants block destructive course and user deletion" do
    grant
    assert_not @course.destroy
    assert_not @user.destroy
    assert @course.reload.persisted?
  end
end
