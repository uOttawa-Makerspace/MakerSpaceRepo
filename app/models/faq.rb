# frozen_string_literal: true

class Faq < ApplicationRecord
  validates :title_en, presence: true
  validates :title_fr, presence: true
  validates :body_en, presence: true
  validates :body_fr, presence: true
end
