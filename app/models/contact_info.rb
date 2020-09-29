class ContactInfo < ApplicationRecord
  has_one :opening_hour, dependent: :destroy
  accepts_nested_attributes_for :opening_hour
end
