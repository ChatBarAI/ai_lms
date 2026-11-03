require "test_helper"

class TerminologyInterpolationTest < ActiveSupport::TestCase
  setup do
    @setting = SiteSetting.current
    @original_terminology = @setting.terminology.deep_dup
  end

  teardown do
    @setting.update!(terminology: @original_terminology)
    TerminologyApplier.call
  end

  # 9acf151 and 239c082 fixed calls like these by hand-adding `**terms`.
  test "translations fill terminology placeholders without the caller passing terms" do
    assert_equal "Courses", I18n.t("layouts.application.courses")
    assert_equal "My courses", I18n.t("layouts.application.my_courses")
    assert_equal "Courses", ApplicationController.new.view_context.t("layouts.application.courses")
  end

  test "admin terminology overrides reach every translation" do
    @setting.update!(terminology: { "en" => { "course_one" => "Module", "course_other" => "Modules" } })
    TerminologyApplier.call

    assert_equal "My modules", I18n.t("layouts.application.my_courses")
    assert_equal "Modules", ApplicationController.helpers.terms[:courses]
  end

  test "explicit interpolation values win over terminology" do
    assert_equal "Algebra", I18n.t("layouts.application.courses", courses: "Algebra")
  end
end
