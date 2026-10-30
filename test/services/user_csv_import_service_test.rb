require "test_helper"
require "stringio"

class UserCsvImportServiceTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "email-only import normalizes emails and defaults to student" do
    assert_no_emails do
      assert_difference -> { User.count }, 1 do
        result = import("email\n  New.Student@Example.com  \n")
        assert result.success?, result.errors.inspect
        assert_equal 1, result.created
      end
    end
    user = User.find_by!(email: "new.student@example.com")
    assert user.student?
    assert_nil user.organization
    assert user.encrypted_password.present?
  end

  test "imports full names roles and organizations by name or slug" do
    result = import("email,full_name,role,organization\na@example.com,\"Doe, Alex\",instructor,ACME CORP\nb@example.com,Bee,admin,globex\n")
    assert result.success?, result.errors.inspect
    user = User.find_by!(email: "a@example.com")
    assert_equal "Doe, Alex", user.name
    assert user.instructor?
    assert_equal organizations(:acme), user.organization
    assert User.find_by!(email: "b@example.com").admin?
    assert_equal organizations(:globex), User.find_by!(email: "b@example.com").organization
  end

  test "accepts BOM human-readable headers and blank optional values" do
    result = import("\uFEFFEmail,Full Name,Role,Organization\nnew@example.com,New User,,\n")
    assert result.success?, result.errors.inspect
    assert_equal "New User", User.find_by!(email: "new@example.com").name
    assert User.find_by!(email: "new@example.com").student?
  end

  test "skips existing and duplicate accounts without updating them" do
    original = users(:student).attributes
    result = import("email,name,role\nSTUDENT@example.com,Changed,admin\nnew@example.com,First,\nNEW@example.com,Second,admin\n")
    assert result.success?, result.errors.inspect
    assert_equal 1, result.created
    assert_equal 2, result.skipped
    assert_equal original, users(:student).reload.attributes
    assert_equal "First", User.find_by!(email: "new@example.com").name
    assert User.find_by!(email: "new@example.com").student?
  end

  test "rolls back all accounts and reports invalid rows" do
    assert_no_difference -> { User.count } do
      result = import("email,role,organization\ngood@example.com,,\nbad-email,,\nrole@example.com,owner,\norg@example.com,,Missing Org\n")
      assert_not result.success?
      assert_equal 0, result.created
      assert_equal 3, result.errors.size
      assert_match "Row 3", result.errors[0]
      assert_match "Row 4", result.errors[1]
      assert_match "Row 5", result.errors[2]
    end
  end

  test "rejects missing file malformed CSV invalid encoding and invalid headers" do
    assert_not UserCsvImportService.new(nil).call.success?
    [ "email\n\"unclosed", "email\n\xFF".b, "name\nName\n", "email,email\na,b\n",
      "email,rol\na@example.com,admin\n", "email,name,full_name\na@example.com,A,B\n",
      "email\n", "email\na@example.com,extra\n", "email\n,\n" ].each do |csv|
      assert_no_difference -> { User.count } do
        assert_not import(csv).success?, csv.inspect
      end
    end
  end

  test "rejects null bytes in headers and account fields without creating accounts" do
    [ "email\0,name,organization\nbad@example.com,Alex,\n",
      "email,name,organization\nbad\0@example.com,Alex,\n",
      "email,name,organization\ngood@example.com,Good,\nbad@example.com,Alex\0Test,\n",
      "email,name,organization\nbad@example.com,Alex,Acme\0Corp\n" ].each do |csv|
      assert_no_difference -> { User.count } do
        result = import(csv)
        assert_not result.success?
        assert_equal 0, result.created
        assert_equal [ "CSV file must not contain null bytes." ], result.errors
      end
    end
  end

  test "accepts 250 rows and rejects 251 rows" do
    csv = "email\n" + ("#{users(:student).email}\n" * 250)
    assert_no_difference -> { User.count } do
      result = import(csv)
      assert result.success?, result.errors.inspect
      assert_equal 250, result.skipped

      result = import(csv + "new@example.com\n")
      assert_not result.success?
      assert_equal [ "CSV must contain at most 250 accounts." ], result.errors
    end
  end

  test "rejects oversized files and excessive rows" do
    assert_not import("x" * (UserCsvImportService::MAX_BYTES + 1)).success?
    result = import("email\n" + ("new@example.com\n" * (UserCsvImportService::MAX_ROWS + 1)))
    assert_not result.success?
    assert_match "at most", result.errors.first
  end

  private

  def import(csv)
    UserCsvImportService.new(StringIO.new(csv)).call
  end
end
