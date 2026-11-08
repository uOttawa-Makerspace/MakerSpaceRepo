# frozen_string_literal: true

class Faq < ApplicationRecord
  include Translatable

  translates :title, :body, prefix: "localized_"

  validates :title_en, presence: true
  validates :title_fr, presence: true
  validates :body_en, presence: true
  validates :body_fr, presence: true
  validates :order, numericality: { only_integer: true, allow_nil: true }
  default_scope { order :order }

end
