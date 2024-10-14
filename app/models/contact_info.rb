class ContactInfo < ApplicationRecord
  has_many :opening_hours, dependent: :destroy
  accepts_nested_attributes_for :opening_hours,
                                allow_destroy: true, # add '_destroy': true to destroy a record
                                reject_if:
                                  lambda { |attributes|
                                    attributes["target_en"].blank? ||
                                      attributes["target_fr"].blank?
                                  }
end
