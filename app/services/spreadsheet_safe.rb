# CSV quoting alone does not prevent spreadsheet formula evaluation.
module SpreadsheetSafe
  def self.cell(value)
    return value unless value.is_a?(String)

    # Include leading whitespace/control characters which importers may strip.
    value.match?(/\A(?:[\x00-\x20]*[=+@-]|[\t\r\n])/) ? "'#{value}" : value
  end
end
