class OpeningHour < ApplicationRecord
  belongs_to :contact_info, optional: true
end
