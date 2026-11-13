# frozen_string_literal: true

# Added to ActiveStorage::Blob (config/initializers/stock_file_guard.rb).
module JobOrderBlob
  # What can make a stored file a job order's: the order itself, its tasks and its task options (the legacy option
  # rows share their blob with a task option).
  JOB_ORDER_OWNERS = %w[JobOrder JobTask JobTaskOption JobOrderOption].freeze

  # True when the stored file, or the original a variant was made from, is attached to a job order. Such a file is
  # served only by JobOrders::FilesController, which checks who is signed in.
  def job_order_file?(owners = attachment_owners)
    owners.any? do |type, owner_id|
      JOB_ORDER_OWNERS.include?(type) || (type == "ActiveStorage::VariantRecord" && job_order_variant?(owner_id))
    end
  end

  private

  def job_order_variant?(variant_record_id)
    ActiveStorage::VariantRecord.find_by(id: variant_record_id)&.blob&.job_order_file? || false
  end
end
