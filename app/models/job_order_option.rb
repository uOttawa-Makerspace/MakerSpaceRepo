# A legacy option row of a job order (the table predates job task options). Its file is also attached
# to the matching job task option on the same blob, so deleting a row never purges the file.
class JobOrderOption < ApplicationRecord
  belongs_to :job_order
  belongs_to :job_option

  has_one_attached :option_file, dependent: false
end
