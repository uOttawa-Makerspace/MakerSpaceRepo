# frozen_string_literal: true

# Integer#ordinalize (and the :long_ordinal date format built on it) asks I18n for
# number.nth.ordinalized. ActiveSupport ships that only for English, so in French it raised in
# development and test and printed English suffixes ("3rd") in production. Ruby values, not YAML,
# because the suffix depends on the number.
{
  en: {
    date: {
      # The day of the month as written in a date: 1st, 2nd, 3rd.
      day_ordinal: ->(_key, options) { ActiveSupport::Inflector.ordinalize(options[:number]) }
    }
  },
  fr: {
    date: {
      # "1er novembre", then plain numbers: "2 novembre".
      day_ordinal: ->(_key, options) { options[:number] == 1 ? "1er" : options[:number].to_s }
    },
    number: {
      # "1 234,50": comma decimal separator, no-break space between thousands.
      format: { separator: ",", delimiter: "\u00A0" },
      # "58,50 $": the symbol follows the amount, joined by a no-break space so the two never wrap apart.
      currency: { format: { format: "%n\u00A0%u", unit: "$", separator: ",", delimiter: "\u00A0" } },
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
