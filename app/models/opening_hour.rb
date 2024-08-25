class OpeningHour < ApplicationRecord
  belongs_to :contact_info, optional: true

  # this returns html
  def formatted(field)
    tag_map = I18n.t("hours.tags").transform_keys { |k| "[#{k.upcase}]" }
    # copy field
    formatted = self[field]
    # transform simple tags
    tag_map.each { |tag, value| formatted.gsub!(tag, value) }
    # transform locale specific tags [EN=text text] or [FR=text text]
    # This uses a regex, searched for a pattern replaces with
    # a captured group note text text
    # This is rather convoluted, but I'd admit is somewhat easier
    # than making a whole new table for this
    # Get all locales
    I18n.available_locales.each do |locale|
      # interpolate locale regex
      # /\[EN=(.*?)\]/
      # /\[FR=(.*?)\]/
      locale_tag = /\[#{locale.to_s.upcase}=(.*?)\]/
      # Replace with first capture group \1
      # or empty string if not current locale
      formatted.gsub!(locale_tag, I18n.locale == locale ? '\1' : "")
    end

    return formatted
  end
end
