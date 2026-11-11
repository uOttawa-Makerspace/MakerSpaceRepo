# frozen_string_literal: true

class OrderItem < ApplicationRecord
  WAITING = "Waiting for approval"
  AWARDED = "Awarded"
  REVOKED = "Revoked"
  REVOKED_BADGE_REASON = Certification::BADGE_REVOKED_REASON

  belongs_to :proficient_project, optional: true
  belongs_to :order, optional: true
  has_many_attached :files
  validates :files,
            file_content_type: {
              allow: %w[
                application/pdf
                image/svg+xml
                text/html
                text/css
                text/javascript
                text/ino
                text/x-java-source
                model/stl
                application/vnd.ms-pki.stl
                application/octet-stream
                text/plain
                model/x.stl-binary
                model/x.stl-binary
                text/x.gcode
                image/vnd.dxf
                image/x-dxf
                image/png
                image/jpg
                image/jpeg
                image/gif
                image/webp
                model/x.stl-ascii
              ],
              if: -> { files.attached? }
            }
  validates :quantity,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than: 0
            }
  # The project is fixed once the item exists: its unit_price snapshot and the badge-requirement
  # check (on add) belong to that project, so swapping it would buy another project at the old
  # price. Assigning it on a persisted item raises ActiveRecord::ReadonlyAttributeError.
  attr_readonly :proficient_project_id
  validate :product_present
  validate :order_present
  before_save :finalize
  scope :completed_order,
        -> {
          joins(order: :order_status).where(
            order_statuses: {
              name: "Completed"
            }
          )
        }
  scope :in_progress, -> { where(status: "In progress") }
  scope :awarded, -> { where(status: "Awarded") }
  scope :waiting_for_approval, -> { where(status: "Waiting for approval") }

  def unit_price
    persisted? ? self[:unit_price] : proficient_project.cc
  end

  def total_price
    unit_price * quantity
  end

  # THE price of this item (Order#priced_items): its price snapshot x quantity in whole CC, what
  # the cart shows, what is stored and what checkout charges; nil when the item can no longer be
  # bought (fails validation), shown as needing removal and never charged.
  def charge
    valid? ? total_price.to_i : nil
  end

  # What a checked-out item was charged, exactly as stored when it was checked out (a whole-CC
  # amount for current rows; a legacy row may hold a fraction, which is never rounded), or nil for
  # a legacy row that never stored one. Never raises, unlike total_price, which multiplies the
  # nullable unit_price and quantity.
  def paid_amount
    self[:total_price]
  end

  # Revokes the item. The certifications its approvals granted are deactivated like a demotion
  # (rows and history stay), unless another awarded item of the same user, training and level still
  # backs the badge. Revoking a revoked item changes nothing. Returns false, with the reasons on the item
  # and nothing written, when the item does not save; a certification that cannot be saved raises
  # (RecordInvalid) and rolls everything back.
  def revoke(staff)
    transaction do
      lock_project_items
      if revoked?
        true
      elsif update(status: "Revoked")
        deactivate_badge(staff)
        true
      else
        false
      end
    end
  end

  # Approves a submission that is waiting for approval or was revoked, and grants the project's
  # badge: a certification this user lost to a badge revoke is reactivated (the most recent one),
  # otherwise a new one is created unless the user already holds an active one for the same
  # training and level (then the approval is kept and no second certification is made).
  # Any other status returns false and writes nothing.
  def award!(staff, attributes = {})
    transaction do
      lock_project_items
      if awardable?
        grant_badge(staff)
        update!(attributes.merge(status: "Awarded"))
        true
      else
        false
      end
    end
  end

  def revoked?
    status == REVOKED
  end

  def awarded?
    status == AWARDED
  end

  def waiting?
    status == WAITING
  end

  private

  def awardable?
    waiting? || revoked?
  end

  # Revoke and award serialize per user, training and level: every item of that set is locked in id
  # order before any status is read, so two admins acting on items that back the same certification
  # never both see the other as still awarded. Reloads, so the status read afterwards is the locked one.
  def lock_project_items
    project_items.order(:id).lock.pluck(:id)
    reload
  end

  # The user's items for projects of the same training and level, this one included.
  def project_items
    if order
      OrderItem.where(
        proficient_project_id: ProficientProject.where(training_id: proficient_project.training_id, level: proficient_project.level).select(:id),
        order_id: Order.where(user_id: order.user_id).select(:id)
      )
    else
      OrderItem.where(id: id)
    end
  end

  def granted_certifications
    Certification.for_projects(order.user_id, proficient_project.training_id, proficient_project.level)
  end

  # A certification the user already holds for the training and level is reused (no project
  # session, no second row); otherwise a badge a revoke deactivated is restored, or a new one made.
  def grant_badge(staff)
    cert = Certification.certify_for_project(order.user_id, proficient_project.training_id, proficient_project.level, restore: granted_certifications)
    return unless cert.previously_new_record? || cert.saved_change_to_active?

    ProficientProjectSession.create!(
      proficient_project_id: proficient_project.id,
      level: proficient_project.level,
      user_id: staff.id,
      certification_id: cert.id
    )
  end

  def deactivate_badge(staff)
    return if other_awarded_items.exists?

    granted_certifications.where(active: true).find_each do |cert|
      cert.update!(active: false, demotion_reason: Certification::BADGE_REVOKED_REASON, demotion_staff: staff)
    end
  end

  def other_awarded_items
    project_items.awarded.where.not(id: id)
  end

  def product_present
    errors.add(:proficient_project, :not_valid) if proficient_project.nil?
  end

  def order_present
    errors.add(:order, :not_a_valid_order) if order.nil?
  end

  def finalize
    self[:unit_price] = unit_price
    self[:total_price] = quantity * self[:unit_price]
  end
end
