class JobQuoteLineItem < ApplicationRecord
  belongs_to :job_order

  validates :description, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
end
