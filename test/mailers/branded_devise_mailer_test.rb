require "test_helper"

class BrandedDeviseMailerTest < ActionMailer::TestCase
  test "password email uses setup wording only before the first sign-in" do
    user = users(:student)
    [ [ 0, "Set" ], [ 1, "Reset" ] ].each do |count, action|
      user.update!(sign_in_count: count)
      email = BrandedDeviseMailer.reset_password_instructions(user, "reset-token")
      assert_equal "#{action} your password", email.subject
      assert_includes email.html_part.body.decoded, "#{action} password"
      assert_includes email.text_part.body.decoded, "#{action} your password"
      assert_includes email.html_part.body.decoded, "reset_password_token=reset-token"
    end
  end

  test "password reset email uses site branding and embeds the uploaded logo" do
    setting = SiteSetting.current
    setting.update!(
      brand_name: "Acme Academy",
      page_bg_light: "#f1f5f9",
      brand_primary_color: "#123456",
      btn_primary_fg_light: "#ffffff"
    )
    setting.logo.attach(
      io: file_fixture("poster.png").open,
      filename: "acme-logo.png",
      content_type: "image/png"
    )

    email = BrandedDeviseMailer.reset_password_instructions(users(:student), "reset-token")
    html = email.html_part.body.decoded
    logo = email.attachments.find(&:inline?)

    assert_includes html, "Acme Academy"
    assert_includes html, "Hello Student One,"
    assert_includes html, "#123456"
    assert_includes html, "reset_password_token=reset-token"
    assert_match(/src=["']cid:/, html)
    assert_equal "brand-logo.png", logo.filename
    assert_equal "image/png", logo.content_type
  end

  test "password reset email embeds the built-in logo when no logo is uploaded" do
    SiteSetting.current.logo.purge

    email = BrandedDeviseMailer.reset_password_instructions(users(:student), "reset-token")
    logo = email.attachments.find(&:inline?)

    assert_equal "brand-logo.png", logo.filename
    assert logo.body.decoded.present?
  end

  test "password reset email falls back to the email address when the name is blank" do
    user = users(:student)
    user.update!(name: nil)

    email = BrandedDeviseMailer.reset_password_instructions(user, "reset-token")

    assert_includes email.html_part.body.decoded, "Hello student@example.com,"
    assert_includes email.text_part.body.decoded, "Hello student@example.com,"
  end
end
