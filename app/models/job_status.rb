class JobStatus < ApplicationRecord
  has_many :job_order_statuses, dependent: :destroy
  validates :name, presence: true, uniqueness: true

  DRAFT = JobStatus.find_by(name: "Draft")
  STAFF_APPROVAL = JobStatus.find_by(name: "Waiting for Staff Approval")
  USER_APPROVAL = JobStatus.find_by(name: "Waiting for User Approval")
  SENT_REMINDER = JobStatus.find_by(name: "Sent a Quote Reminder")
  WAITING_PROCESSED = JobStatus.find_by(name: "Waiting to be Processed")
  BEING_PROCESSED = JobStatus.find_by(name: "Currently being Processed")
  COMPLETED = JobStatus.find_by(name: "Completed (Waiting for Payment)")
  PAID = JobStatus.find_by(name: "Paid (Waiting for Pick-Up)")
  PICKED_UP = JobStatus.find_by(name: "Picked-Up")
  DECLINED = JobStatus.find_by(name: "Declined")

  def t_name
    I18n.locale == :fr ? name_fr : name
  end

  def t_description
    I18n.locale == :fr ? description_fr : description
  end
end
