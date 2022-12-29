class JobTypeExtra < ApplicationRecord
  belongs_to :job_type, optional: true
  has_many :job_order_quote_type_extras
  validates :name, presence: true
end
