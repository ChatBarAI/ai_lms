require "test_helper"

class ActiveStorageAccessControlTest < ActionDispatch::IntegrationTest
  test "anonymous user cannot access a course asset" do
    courses(:other_owner_course).cover_image.attach(image_upload("course-cover.png"))

    get rails_blob_path(courses(:other_owner_course).cover_image)

    assert_response :unauthorized
  end

  test "anonymous user can access a public course asset" do
    courses(:algebra).cover_image.attach(image_upload("course-cover.png"))

    get rails_blob_path(courses(:algebra).cover_image)

    assert_response :success
  end

  test "signed in user can access a course asset" do
    courses(:algebra).cover_image.attach(image_upload("course-cover.png"))
    sign_in users(:student)

    get rails_blob_path(courses(:algebra).cover_image)

    assert_response :success
  end

  test "anonymous user cannot access a lesson asset" do
    lessons(:physics_lesson).poster_image.attach(image_upload("poster.png"))

    get rails_blob_path(lessons(:physics_lesson).poster_image)

    assert_response :unauthorized
  end

  test "anonymous user cannot access a lesson material document" do
    material = LessonMaterial.new(lesson: lessons(:physics_lesson), title: "Notes", kind: :pdf)
    material.document.attach(
      io: StringIO.new("%PDF-1.4\n"),
      filename: "notes.pdf",
      content_type: "application/pdf"
    )
    material.save!

    get rails_blob_path(material.document)

    assert_response :unauthorized
  end

  test "anonymous user cannot access a trix image attached to a lesson body" do
    blob = attach_trix_image_to(lessons(:physics_lesson))

    get rails_blob_path(blob)

    assert_response :unauthorized
  end

  test "anonymous user can access a trix image attached to a public lesson body" do
    blob = attach_trix_image_to(lessons(:intro))

    get rails_blob_path(blob)

    assert_response :success
  end

  test "public course asset is protected when guest access is disabled" do
    SiteSetting.current.update!(allow_guest_access: false)
    courses(:algebra).cover_image.attach(image_upload("course-cover.png"))

    get rails_blob_path(courses(:algebra).cover_image)

    assert_response :unauthorized
  ensure
    SiteSetting.current.update!(allow_guest_access: true)
  end

  test "anonymous user cannot access a trix image representation" do
    blob = attach_trix_image_to(lessons(:physics_lesson))
    representation = blob.representation(resize_to_limit: [ 100, 100 ])

    get rails_representation_path(representation)

    assert_response :unauthorized
  end

  test "site setting logo remains public" do
    SiteSetting.current.logo.attach(image_upload("logo.png"))

    get rails_blob_path(SiteSetting.current.logo)

    assert_response :success
  end

  test "direct uploads require authentication" do
    post rails_direct_uploads_path, params: {
      blob: {
        filename: "upload.png",
        byte_size: 1,
        checksum: "abc",
        content_type: "image/png"
      }
    }

    assert_response :unauthorized
  end

  private

  def attach_trix_image_to(lesson)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join("test/fixtures/files/poster.png")),
      filename: "trix-image.png",
      content_type: "image/png"
    )
    lesson.update!(
      body: %(<p>Image:</p><action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>)
    )
    blob
  end

  def image_upload(_filename)
    Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/poster.png"), "image/png", true)
  end
end
