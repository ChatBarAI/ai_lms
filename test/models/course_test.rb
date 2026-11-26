require "test_helper"

class CourseTest < ActiveSupport::TestCase
  test "learning order is optional and non-negative" do
    course = courses(:algebra)
    assert course.update(learning_order: nil)
    assert course.update(learning_order: 0)

    assert_not course.update(learning_order: -1)
    assert_includes course.errors[:learning_order], "must be greater than or equal to 0"
  end

  test "valid fixture" do
    assert courses(:algebra).valid?
  end

  test "only instructors and admins can own courses" do
    [ users(:instructor), users(:admin) ].each do |owner|
      course = Course.new(title: "Eligible Owner", owner: owner)
      assert course.valid?, course.errors.full_messages.inspect
    end

    course = Course.new(title: "Student Owner", owner: users(:student))
    assert_not course.save
    assert_includes course.errors[:owner], "must be an instructor or admin"
  end

  test "cannot transfer a course to a student" do
    course = courses(:algebra)
    original_owner = course.owner

    assert_not course.update(owner: users(:student))
    assert_includes course.errors[:owner], "must be an instructor or admin"
    assert_equal original_owner, course.reload.owner
  end

  test "requires title and owner; subject is optional" do
    c = Course.new
    assert_not c.valid?
    assert_includes c.errors[:title], "can't be blank"
    assert_empty c.errors[:subject]
    assert_includes c.errors[:owner], "must exist"
  end

  test "blank title only reports a title error" do
    [ nil, "", "   " ].each do |title|
      course = Course.new(title: title, owner: users(:instructor))

      assert_not course.valid?
      assert_equal [ "Title can't be blank" ], course.errors.full_messages
    end
  end

  test "slug validation still rejects titles that generate an empty slug" do
    course = Course.new(title: "!!!", owner: users(:instructor))

    assert_not course.valid?
    assert_includes course.errors[:slug], "can't be blank"
    assert_includes course.errors[:slug], "is invalid"
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
end
