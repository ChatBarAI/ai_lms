require "test_helper"

class SiteSettingTest < ActiveSupport::TestCase
  test "current creates a record on first call" do
    SiteSetting.delete_all
    assert_difference -> { SiteSetting.count }, 1 do
      SiteSetting.current
    end
  end

  test "current is idempotent" do
    SiteSetting.current
    assert_no_difference -> { SiteSetting.count } do
      SiteSetting.current
    end
  end

  test "allow_guest_access defaults to true" do
    SiteSetting.delete_all
    assert SiteSetting.current.allow_guest_access?
  end

  test "ask_help_available_for requires enabled flag and token" do
    s = SiteSetting.current
    s.update!(help_enabled: false, help_admin_token: "tok")
    assert_not s.ask_help_available_for?(:admin)

    s.update!(help_enabled: true, help_admin_token: "")
    assert_not s.ask_help_available_for?(:admin)

    s.update!(help_enabled: true, help_admin_token: " help-lms-admin ")
    assert s.ask_help_available_for?(:admin)
    assert_equal "help-lms-admin", s.ask_help_token_for(:admin)
    assert s.ask_help_available_for?(:instructor)
    assert_equal "help-lms-admin", s.ask_help_token_for(:instructor)

    s.update!(help_instructor_token: "help-lms-instructor")
    assert_equal "help-lms-instructor", s.ask_help_token_for(:instructor)
  end

  test "logo rejects non-image content types" do
    s = SiteSetting.current
    s.logo.attach(io: StringIO.new("x"), filename: "x.txt", content_type: "text/plain")
    assert_not s.valid?
    assert s.errors[:logo].any?
  end

  test "normalises legacy flat terminology as English overrides" do
    s = SiteSetting.current
    s.terminology = {
      "lesson_one" => "Module",
      "lesson_other" => "Modules"
    }

    assert s.valid?, s.errors.full_messages.inspect
    assert_equal "Module", s.terminology["en"]["lesson_one"]
    assert_equal "Modules", s.terminology["en"]["lesson_other"]
  end

  test "keeps terminology overrides scoped to their locale" do
    s = SiteSetting.current
    s.update!(terminology: {
      "en" => {
        "lesson_one" => "Module",
        "lesson_other" => "Modules"
      },
      "de" => {
        "lesson_one" => "Modul",
        "lesson_other" => "Module"
      }
    })

    TerminologyApplier.call

    assert_equal "Module", I18n.with_locale(:en) { Lesson.model_name.human(count: 1) }
    assert_equal "Modules", I18n.with_locale(:en) { Lesson.model_name.human(count: 2) }
    assert_equal "Modul", I18n.with_locale(:de) { Lesson.model_name.human(count: 1) }
    assert_equal "Module", I18n.with_locale(:de) { Lesson.model_name.human(count: 2) }
  ensure
    s&.update!(terminology: {})
    TerminologyApplier.call
  end
end
