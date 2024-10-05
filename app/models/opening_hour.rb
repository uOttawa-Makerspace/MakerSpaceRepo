class OpeningHour < ApplicationRecord
  belongs_to :contact_info

  default_scope -> { order(:id) }

  delegate :tag, to: "ApplicationController.helpers"

  def notes
    I18n.locale == :fr ? notes_fr : notes_en
  end

  def target
    I18n.locale == :fr ? target_fr : target_en
  end

  # this returns html
  def formatted(field)
    return "" # nah
    # copy field
    formatted = self[field]
    formatted.gsub!(/&nbsp;/i, "")
    # transform simple tags
    tag_map = I18n.t("hours.tags").transform_keys &:to_s
    tag_map.each { |tag, value| formatted.gsub!("[#{tag.upcase}]", value) }

    # tags in the form of [SUNDAY | 9am - 5pm]
    # are split into two spans and put in a div
    # the div is later justified with a global css
    time_day_splitter = /\[(.+?)\|(.+?)\]/
    formatted.gsub!(time_day_splitter) do
      # catch extra spaces, trix keeps them.
      left = $1.squish
      right = $2.squish
      tag.div class: "formatted-hour-row" do
        tag.span(tag_map[left.downcase] || left) +
          tag.span(tag_map[right.downcase] || right)
      end
    end

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
