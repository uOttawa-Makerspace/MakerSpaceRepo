class PrinterIssue < ApplicationRecord
  belongs_to :printer
  belongs_to :reporter, class_name: "User", foreign_key: :reporter_id
end
