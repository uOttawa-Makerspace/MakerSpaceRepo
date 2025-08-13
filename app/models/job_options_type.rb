class JobOptionsType < ApplicationRecord
  belongs_to :job_option
  belongs_to :job_type
end
