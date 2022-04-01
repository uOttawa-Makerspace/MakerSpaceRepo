class JobStatus < ApplicationRecord
  has_many :job_order_statuses, dependent: :destroy
  validates :name, presence: true, uniqueness: true

  DRAFT = JobStatus.find_by(name: 'Draft')
  STAFF_APPROVAL = JobStatus.find_by(name: 'Waiting for Staff Approval')
  USER_APPROVAL = JobStatus.find_by(name: 'Waiting for User Approval')
  WAITING_PROCESSED = JobStatus.find_by(name: 'Waiting to be Processed')
  PROCESSED = JobStatus.find_by(name: 'Processed')
  PAID = JobStatus.find_by(name: 'Paid')
  PICKED_UP = JobStatus.find_by(name: 'Picked-Up')
  DECLINED = JobStatus.find_by(name: 'Declined')
end