class JobOption < ApplicationRecord
  has_and_belongs_to_many :job_types
  has_many :job_order_quote_options
  has_and_belongs_to_many :job_orders
  validates :name, presence: true, uniqueness: true
  validates :fee, presence: true

  has_many_attached :files

  def name_with_description
    "#{name} #{"(#{description})" if description.present?}"
  end
end
