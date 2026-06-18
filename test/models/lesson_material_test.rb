require "test_helper"

class LessonMaterialTest < ActiveSupport::TestCase
  setup do
    @lesson = lessons(:intro)
  end

  test "html material requires body" do
    r = LessonMaterial.new(lesson: @lesson, title: "T", kind: :html)
    assert_not r.valid?
    assert_includes r.errors[:body], "can't be blank"
  end

  test "pdf material requires document" do
    r = LessonMaterial.new(lesson: @lesson, title: "T", kind: :pdf)
    assert_not r.valid?
    assert_includes r.errors[:document], "must be attached for a PDF material"
  end

  test "html material saves with body" do
    r = LessonMaterial.new(lesson: @lesson, title: "T", kind: :html)
    r.body = "<p>Hello</p>"
    assert r.save, r.errors.full_messages.to_sentence
  end

  test "assigns next position on create" do
    LessonMaterial.create!(lesson: @lesson, title: "A", kind: :html, body: "x")
    r2 = LessonMaterial.create!(lesson: @lesson, title: "B", kind: :html, body: "y")
    assert r2.position >= 1
  end

  test "audio_url material requires url" do
    r = LessonMaterial.new(lesson: @lesson, title: "T", kind: :audio_url)
    assert_not r.valid?
    assert_includes r.errors[:url], "can't be blank"
  end

  test "image_upload material requires image file" do
    r = LessonMaterial.new(lesson: @lesson, title: "Image", kind: :image_upload)
    assert_not r.valid?
    assert_includes r.errors[:image_file], "must be attached for an uploaded image material"
  end
end

class LessonMaterialsGatingTest < ActiveSupport::TestCase
  setup do
    @lesson = lessons(:intro)
    @enrollment = enrollments(:student_in_algebra)
  end

  test "complete? returns true when no required materials" do
    assert @lesson.lesson_materials_complete_for?(@enrollment)
  end

  test "complete? false until all required materials acknowledged" do
    m1 = LessonMaterial.create!(lesson: @lesson, title: "M1", kind: :html, body: "a", required: true)
    m2 = LessonMaterial.create!(lesson: @lesson, title: "M2", kind: :html, body: "b", required: false)

    assert_not @lesson.lesson_materials_complete_for?(@enrollment)

    LessonMaterialAcknowledgement.create!(lesson_material: m1, enrollment: @enrollment)
    @lesson.reload
    assert @lesson.lesson_materials_complete_for?(@enrollment)
    assert m2.acknowledged_by?(@enrollment) == false
  end
end
