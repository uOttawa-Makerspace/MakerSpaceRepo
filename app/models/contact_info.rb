class ContactInfo < ApplicationRecord
  has_many :opening_hours, dependent: :destroy
  accepts_nested_attributes_for :opening_hours,
                                allow_destroy: true, # add '_destroy': true to destroy a record
                                reject_if:
                                  lambda { |attributes|
                                    attributes["target_en"].blank? ||
                                      attributes["target_fr"].blank?
                                  }

  # Periods a visitor may see: those not hidden for the whole week.
  def public_opening_hours
    opening_hours.reject(&:hidden_closed_all_week?)
  end
end
