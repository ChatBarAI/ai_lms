require "test_helper"

class RatingTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert ratings(:student_intro_rating).valid?
  end

  test "stars optional and constrained to 1..5 integer when present" do
    r = Rating.new(user: users(:other_student), lesson: lessons(:intro))
    assert r.valid?
    r.stars = 0
    assert_not r.valid?
    r.stars = 6
    assert_not r.valid?
    r.stars = 3
    assert r.valid?
  end

  test "user+lesson uniqueness" do
    dup = Rating.new(user: users(:student), lesson: lessons(:intro), stars: 4)
    assert_not dup.valid?
  end
end
