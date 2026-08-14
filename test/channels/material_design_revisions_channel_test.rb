require "test_helper"

class MaterialDesignRevisionsChannelTest < ActionCable::Channel::TestCase
  test "owner subscribes and receives the current revision states" do
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Designed material", kind: :raw_html_iframe,
      raw_html_content: "<html><body>Material</body></html>"
    )
    configuration = AiModelConfiguration.create!(
      name: "Test model", provider: "openai", model: "test-model",
      base_url: "https://api.openai.com/v1", api_key: "secret"
    )
    revision = material.material_design_revisions.create!(
      ai_model_configuration: configuration, created_by: users(:instructor),
      request: "Improve the layout", status: "queued"
    )
    stub_connection current_user: users(:instructor)

    subscribe lesson_material_id: material.id

    assert subscription.confirmed?
    assert_has_stream MaterialDesignRevision.stream_name_for(material.id)
    assert_equal "snapshot", transmissions.last["event"]
    assert_equal revision.id, transmissions.last["revisions"].first["revision_id"]
    assert_equal "queued", transmissions.last["revisions"].first["status"]
  end

  test "another instructor cannot subscribe" do
    material = LessonMaterial.create!(
      lesson: lessons(:intro), title: "Designed material", kind: :raw_html_iframe,
      raw_html_content: "<html><body>Material</body></html>"
    )
    stub_connection current_user: users(:other_instructor)

    subscribe lesson_material_id: material.id

    assert subscription.rejected?
  end
end
