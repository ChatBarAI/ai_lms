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
end
