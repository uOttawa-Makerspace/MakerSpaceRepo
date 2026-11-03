# frozen_string_literal: true

# Integer#ordinalize (and the :long_ordinal date format built on it) asks I18n for
# number.nth.ordinalized. ActiveSupport ships that only for English, so in French it raised in
# development and test and printed English suffixes ("3rd") in production. Ruby values, not YAML,
# because the suffix depends on the number.
{
  fr: {
    number: {
      nth: {
        # "1er", "2e", "3e". Words that need the feminine ("1re année") spell that out in their own
        # translation instead of using the ordinal.
        ordinals: lambda do |_key, options|
          options[:number].to_i.abs == 1 ? "er" : "e"
        end,

        ordinalized: lambda do |_key, options|
          number = options[:number]
          "#{number}#{ActiveSupport::Inflector.ordinal(number)}"
        end
      }
    }
  }
}
