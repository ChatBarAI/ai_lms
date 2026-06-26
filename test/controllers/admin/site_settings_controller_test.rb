require "test_helper"

class Admin::SiteSettingsControllerTest < ActionDispatch::IntegrationTest
  test "non-admin redirected from edit" do
    sign_in users(:instructor)
    get edit_admin_site_setting_path
    assert_redirected_to root_path
  end

  test "admin can edit site setting" do
    sign_in users(:admin)
    get edit_admin_site_setting_path
    assert_response :success
  end

  test "admin can update brand name" do
    sign_in users(:admin)
    patch admin_site_setting_path, params: { section: "branding", site_setting: { brand_name: "New Brand" } }
    assert_equal "New Brand", SiteSetting.current.brand_name
  end

  test "admin can update brand primary color" do
    sign_in users(:admin)
    patch admin_site_setting_path, params: {
      section: "branding",
      site_setting: { brand_primary_color: "#0ea5e9" }
    }

    assert_equal "#0ea5e9", SiteSetting.current.reload.brand_primary_color
  end

  test "section update only applies permitted attributes" do
    sign_in users(:admin)
    setting = SiteSetting.current
    original_brand_name = setting.brand_name

    patch admin_site_setting_path, params: {
      section: "integration",
      site_setting: {
        app_url: "https://lms.example.com",
        redis_url: "redis://localhost:6379/2",
        brand_name: "Should Not Persist"
      }
    }

    setting.reload
    assert_equal "https://lms.example.com", setting.app_url
    assert_equal "redis://localhost:6379/2", setting.redis_url
    assert_equal original_brand_name, setting.brand_name
    assert_redirected_to edit_admin_site_setting_path(anchor: "integration")
  end

  test "terminology section updates locale-specific terminology keys" do
    sign_in users(:admin)

    patch admin_site_setting_path, params: {
      section: "terminology",
      site_setting: {
        terminology: {
          en: {
            lesson_one: "Module",
            lesson_other: "Modules"
          },
          de: {
            lesson_one: "Modul",
            lesson_other: "Module"
          }
        }
      }
    }

    setting = SiteSetting.current
    assert_equal "Module", setting.terminology["en"]["lesson_one"]
    assert_equal "Modules", setting.terminology["en"]["lesson_other"]
    assert_equal "Modul", setting.terminology["de"]["lesson_one"]
    assert_equal "Module", setting.terminology["de"]["lesson_other"]
    assert_redirected_to edit_admin_site_setting_path(anchor: "terminology")
  end

  test "purge helper ignores unknown attachment names" do
    controller = Admin::SiteSettingsController.new
    controller.instance_variable_set(:@site_setting, SiteSetting.current)

    assert_nothing_raised do
      controller.send(:purge_attachment, :__send__)
      controller.send(:purge_attachment, :destroy)
      controller.send(:purge_attachment, :class)
    end
  end
end
