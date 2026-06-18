require "test_helper"

class SubjectTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert subjects(:math).valid?
  end

  test "requires name" do
    s = Subject.new(slug: "thing")
    assert_not s.valid?
  end

  test "auto-assigns slug from name on create" do
    s = Subject.create!(name: "History of Art")
    assert_equal "history-of-art", s.slug
  end

  test "auto-assigns slug when blank string is submitted" do
    s = Subject.create!(name: "Modern History", slug: "")
    assert_equal "modern-history", s.slug
  end

  test "to_param returns slug" do
    assert_equal "mathematics", subjects(:math).to_param
  end

  test "slug must be unique" do
    dup = Subject.new(name: "Other", slug: "mathematics")
    assert_not dup.valid?
    assert_includes dup.errors[:slug], "has already been taken"
  end

  test "slug format restricted to lowercase, digits and hyphens" do
    s = Subject.new(name: "Bad", slug: "Bad Slug!")
    assert_not s.valid?
  end
end
