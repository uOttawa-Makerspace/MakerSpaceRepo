# frozen_string_literal: true

# Admin-entered text stored in one column per language (name_en / name_fr). One reader per
# translated attribute, always the same rule: the text in the requested locale, or the other
# language's text when the requested one is blank (nil, "" or whitespace).
#
#   translates :title, :body                       # title / body read title_<locale> / body_<locale>
#   translates :name, prefix: "localized_"         # localized_name reads name_<locale>
#   translates :name, :description, prefix: "t_", bare_en: true
#                                                  # t_name reads name (English) / name_fr
#
# Every reader takes an optional locale (`tier.title(:fr)`) and defaults to I18n.locale. A locale
# the site does not translate into reads as the default locale. When every language is blank the
# requested language's own value is returned, so a blank stays nil or "" as stored.
module Translatable
  extend ActiveSupport::Concern

  class_methods do
    # prefix:  prepended to the reader's name, for models whose bare name is a real column or
    #          already means something else (job_statuses.name is the English column).
    # bare_en: English lives in the bare column (name) instead of name_en; other languages
    #          keep the suffix (name_fr).
    def translates(*attributes, prefix: nil, bare_en: false)
      attributes.each do |attribute|
        define_method(:"#{prefix}#{attribute}") do |locale = I18n.locale|
          translation_for(attribute, locale, bare_en: bare_en)
        end
      end
    end
  end

  private

  def translation_for(attribute, locale, bare_en:)
    locales = I18n.available_locales
    locale = locale.to_s.to_sym
    locale = I18n.default_locale unless locales.include?(locale)

    values = [locale, *(locales - [locale])].map do |candidate|
      self[bare_en && candidate == :en ? attribute : :"#{attribute}_#{candidate}"]
    end

    values.find(&:present?) || values.first
  end
end
