require "test_helper"

class CourseTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert courses(:algebra).valid?
  end

  test "requires title and owner; subject is optional" do
    c = Course.new
    assert_not c.valid?
    assert_includes c.errors[:title], "can't be blank"
    assert_empty c.errors[:subject]
    assert_includes c.errors[:owner], "must exist"
  end

  test "auto-assigns slug from title" do
    c = Course.create!(title: "Hello World", subject: subjects(:math), owner: users(:instructor))
    assert_equal "hello-world", c.slug
  end

  test "locale defaults to English" do
    c = Course.new(title: "Locale Course", owner: users(:instructor))
    assert_equal "en", c.locale
  end

  test "public access is off by default" do
    c = Course.new(title: "Private Course", owner: users(:instructor))
    assert_not c.public_access_enabled?
    assert_not c.public_to_guests?
  end

  test "allows supported locales" do
    c = Course.new(title: "German Course", owner: users(:instructor), locale: "de")
    assert c.valid?
  end

  test "rejects unsupported locales" do
    c = Course.new(title: "Invalid Locale Course", owner: users(:instructor), locale: "fr")
    assert_not c.valid?
    assert_includes c.errors[:locale], "is not included in the list"
  end

  test "to_param uses slug" do
    assert_equal "algebra", courses(:algebra).to_param
  end

  test "slug must be unique" do
    dup = Course.new(title: "Other", slug: "algebra", subject: subjects(:math), owner: users(:instructor))
    assert_not dup.valid?
  end

  test "published? respects published_at" do
    assert courses(:algebra).published?
    assert_not courses(:draft_course).published?
  end

  test "published scope returns only published courses" do
    assert_includes Course.published, courses(:algebra)
    assert_not_includes Course.published, courses(:draft_course)

    scheduled = Course.create!(
      title: "Scheduled Course",
      slug: "scheduled-course",
      subject: subjects(:math),
      owner: users(:instructor),
      published_at: 1.day.from_now
    )

    assert_not scheduled.published?
    assert_not_includes Course.published, scheduled
  end

  test "paid? is false when price_cents is nil" do
    courses(:algebra).update!(price_cents: nil)
    assert_not courses(:algebra).paid?
  end

  test "paid? is false when price_cents is zero" do
    courses(:algebra).update!(price_cents: 0)
    assert_not courses(:algebra).paid?
  end

  test "paid? is true when price_cents is positive" do
    courses(:algebra).update!(price_cents: 2999)
    assert courses(:algebra).paid?
  end

  test "price returns decimal dollar amount" do
    courses(:algebra).update!(price_cents: 1999)
    assert_equal 19.99, courses(:algebra).price
  end

  test "price_in_dollars= converts dollars to cents" do
    c = courses(:algebra)
    c.price_in_dollars = "29.99"
    c.save!
    assert_equal 2999, c.price_cents
  end

  test "price_in_dollars= with zero sets price_cents to nil" do
    c = courses(:algebra)
    c.price_in_dollars = "0"
    c.save!
    assert_nil c.price_cents
  end

  test "price_in_dollars= with blank sets price_cents to nil" do
    c = courses(:algebra)
    c.update!(price_cents: 1000)
    c.price_in_dollars = ""
    c.save!
    assert_nil c.price_cents
  end

  test "price_in_dollars returns nil when course is free" do
    courses(:algebra).update!(price_cents: nil)
    assert_nil courses(:algebra).price_in_dollars
  end

  test "price_in_dollars returns decimal when course is paid" do
    courses(:algebra).update!(price_cents: 500)
    assert_equal 5.0, courses(:algebra).price_in_dollars
  end

  test "free_course getter returns true when price_cents is nil" do
    courses(:algebra).update!(price_cents: nil)
    assert courses(:algebra).free_course
  end

  test "free_course getter returns false when course is paid" do
    courses(:algebra).update!(price_cents: 1000)
    assert_not courses(:algebra).free_course
  end

  test "free_course= true clears price_cents on save" do
    c = courses(:algebra)
    c.update!(price_cents: 1500)
    c.free_course = true
    c.save!
    assert_nil c.reload.price_cents
  end

  test "free_course= false does not clear an existing price" do
    c = courses(:algebra)
    c.update!(price_cents: 1500)
    c.free_course = false
    c.save!
    assert_equal 1500, c.reload.price_cents
  end

  test "free_course= accepts truthy string '1'" do
    c = courses(:algebra)
    c.update!(price_cents: 999)
    c.free_course = "1"
    c.save!
    assert_nil c.reload.price_cents
  end

  test "purchased_by? returns true for free course regardless of user" do
    courses(:algebra).update!(price_cents: nil)
    assert courses(:algebra).purchased_by?(nil)
    assert courses(:algebra).purchased_by?(users(:student))
  end

  test "purchased_by? returns false for nil user on paid course" do
    courses(:algebra).update!(price_cents: 999)
    assert_not courses(:algebra).purchased_by?(nil)
  end

  test "purchased_by? returns true for course owner" do
    courses(:algebra).update!(price_cents: 999)
    assert courses(:algebra).purchased_by?(users(:instructor))
  end

  test "purchased_by? returns true for admin on paid course" do
    courses(:algebra).update!(price_cents: 999)
    assert courses(:algebra).purchased_by?(users(:admin))
  end

  test "purchased_by? returns true after a purchase record exists" do
    c = courses(:algebra)
    c.update!(price_cents: 999)
    CoursePurchase.create!(user: users(:student), course: c, amount_cents: 999)
    assert c.purchased_by?(users(:student))
  end

  test "purchased_by? returns false with no purchase record" do
    courses(:algebra).update!(price_cents: 999)
    assert_not courses(:algebra).purchased_by?(users(:student))
  end
end
