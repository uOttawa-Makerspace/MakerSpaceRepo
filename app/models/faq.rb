# frozen_string_literal: true

class Faq < ApplicationRecord
  validates :title_en, presence: true
  validates :title_fr, presence: true
  validates :body_en, presence: true
  validates :body_fr, presence: true
  validates :order, numericality: { only_integer: true, allow_nil: true }
  default_scope { order :order }

  def localized_body
    I18n.locale == :fr ? body_fr : body_en
  end

  def localized_title
    I18n.locale == :fr ? title_fr : title_en
  end
end
