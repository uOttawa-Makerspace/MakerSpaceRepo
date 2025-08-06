module SoftDelete
  extend ActiveSupport::Concern

  included do
    scope :not_deleted, -> { unscope(where: :is_deleted).where(is_deleted: false) }
  end

  # Soft delete
  def destroy
    run_callbacks(:destroy) do
      update!(is_deleted: true) 
    end
  end

  def delete
    update!(is_deleted: true)
  end

  def update(attributes)
    transaction do
      # ignore if just toggling is_deleted
      return super(attributes) if attributes.keys.map(&:to_s) == ["is_deleted"]

      dup_record = dup
      super(is_deleted: true, name: "#{name} (copy #{Time.now.to_i})") # edit old one to deleted

      dup_record.assign_attributes(attributes)
      dup_record.is_deleted = false
      dup_record.save! # create new one

      # copy services if sg
      if is_a?(JobServiceGroup) && job_services&.any?
        services.each do |service|
          new_service = service.dup
          new_service.service_group_id = dup_record.id
          new_service.save!
        end
      end

      dup_record
    end
  end

  def update!(attributes)
    success = update(attributes)
    raise ActiveRecord::RecordInvalid, self unless success
    true
  end
end