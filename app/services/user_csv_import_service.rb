require "csv"
require "set"

class UserCsvImportService
  MAX_BYTES = 2.megabytes
  MAX_ROWS = 250
  HEADERS = %w[email name full_name role organization].freeze
  Result = Struct.new(:created, :skipped, :errors, keyword_init: true) do
    def success?
      errors.empty?
    end
  end

  def initialize(file)
    @file = file
    @result = Result.new(created: 0, skipped: 0, errors: [])
  end

  def call
    unless @file.respond_to?(:read)
      return failure("Choose a CSV file to upload.")
    end

    text = @file.read(MAX_BYTES + 1).force_encoding(Encoding::UTF_8)
    return failure("CSV file must be no larger than 2 MB.") if text.bytesize > MAX_BYTES
    return failure("CSV file must use UTF-8 encoding.") unless text.valid_encoding?
    return failure("CSV file must not contain null bytes.") if text.include?("\0")

    table = CSV.parse(text.delete_prefix("\uFEFF"), headers: true, skip_blanks: true,
                      header_converters: ->(header) { header.to_s.strip.downcase.tr(" ", "_") })
    headers = table.headers.compact
    return failure("CSV must have an email header.") unless headers.include?("email")
    return failure("CSV contains duplicate headers.") unless headers.uniq == headers
    unknown = headers - HEADERS
    return failure("Unknown CSV headers: #{unknown.join(', ')}.") if unknown.any?
    return failure("Use either name or full_name, not both.") if headers.include?("name") && headers.include?("full_name")
    return failure("CSV must contain at least one account.") if table.empty?
    return failure("CSV must contain at most #{MAX_ROWS} accounts.") if table.size > MAX_ROWS

    seen = Set.new
    User.transaction(requires_new: true) do
      table.each_with_index do |row, index|
        import_row(row, index + 2, seen)
      end
      raise ActiveRecord::Rollback if @result.errors.any?
    end
    @result.created = 0 unless @result.success?
    @result
  rescue CSV::MalformedCSVError
    failure("CSV could not be read. Check its commas and quoted fields.")
  rescue ActiveRecord::RecordNotUnique
    @result.created = 0
    failure("An account was created concurrently. Please upload the file again.")
  end

  private

  def import_row(row, number, seen)
    if row.fields.length != row.headers.compact.length
      @result.errors << "Row #{number}: the number of fields does not match the headers."
      return
    end
    email = row["email"].to_s.strip.downcase
    if email.present? && (seen.include?(email) || User.exists?([ "LOWER(email) = ?", email ]))
      @result.skipped += 1
      return
    end
    seen.add(email)
    role = row["role"].to_s.strip.downcase.presence || "student"
    unless User.roles.key?(role)
      @result.errors << "Row #{number}: role must be student, instructor or admin."
      return
    end

    organization_name = row["organization"].to_s.strip
    if organization_name.present?
      matches = Organization.where("LOWER(name) = :value OR LOWER(slug) = :value", value: organization_name.downcase).limit(2).to_a
      unless matches.one?
        @result.errors << "Row #{number}: organization must match one existing organization name or slug."
        return
      end
      organization = matches.first
    end

    user = User.new(email: email, name: (row["full_name"] || row["name"]).to_s.strip.presence,
                    role: role, organization: organization, password: Devise.friendly_token(32))
    if user.save
      @result.created += 1
    else
      @result.errors << "Row #{number}: #{user.errors.full_messages.to_sentence}."
    end
  end

  def failure(message)
    @result.errors << message
    @result
  end
end
