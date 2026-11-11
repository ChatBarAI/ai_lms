module Payments
  module Currency
    # Deliberate initial allowlist. Integer amounts are entered in the labelled minor unit.
    RULES = { "eur" => [ 2, 50 ], "usd" => [ 2, 50 ], "gbp" => [ 2, 30 ], "jpy" => [ 0, 50 ] }.freeze
    def self.valid_amount?(currency, amount)
      rule = RULES[currency]
      rule && amount.is_a?(Integer) && amount.between?(rule.last, 99_999_999)
    end
  end
end
