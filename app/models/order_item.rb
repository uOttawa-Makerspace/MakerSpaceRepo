# frozen_string_literal: true

class OrderItem < ApplicationRecord
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

  # What a checked-out item was charged, as stored when it was checked out (a whole-CC amount),
  # or nil for a legacy row that never stored one. Never raises, unlike total_price, which
  # multiplies the nullable unit_price and quantity.
  def paid_amount
    self[:total_price]&.to_i
  end

  REVOKED_BADGE_REASON = "Project badge revoked"

  # Revokes the item. The certification its approval granted is deactivated like a demotion (the
  # row and its history stay), unless another awarded item of the same user and project still
  # backs the badge. Revoking an item that is already revoked changes nothing. Returns false (and
  # writes nothing) when the item does not save.
  def revoke!(staff = nil)
    with_lock do
      return true if status == "Revoked"
      return false unless update(status: "Revoked")

      deactivate_badge(staff)
      true
    end
  end

  # Approves a submission waiting for approval, or restores a revoked one whose badge was
  # deactivated by the revoke. Approving anything else returns false and writes nothing.
  def award!(staff, attributes = {})
    with_lock do
      return false unless awardable?

      status == "Revoked" ? restore_badge : grant_badge(staff)
      update!(attributes.merge(status: "Awarded"))
      true
    end
  end

  def awardable?
    status == "Waiting for approval" || (status == "Revoked" && revoked_badges.exists?)
  end

  private

  def grant_badge(staff)
    level = proficient_project.level
    cert = Certification.create!(user_id: order.user_id, level: level)
    ProficientProjectSession.create!(
      proficient_project_id: proficient_project.id,
      level: level,
      user_id: staff.id,
      certification_id: cert.id
    )
  end

  # Certifications this user earned through approvals of this item's project (the session carries
  # no link to the order item itself).
  def granted_certifications
    Certification.unscoped.joins(:proficient_project_session).where(
      user_id: order.user_id,
      proficient_project_sessions: { proficient_project_id: proficient_project_id }
    )
  end

  def revoked_badges
    granted_certifications.where(active: false, demotion_reason: REVOKED_BADGE_REASON)
  end

  def deactivate_badge(staff)
    return if other_awarded_items.exists?

    granted_certifications.where(active: true).find_each do |cert|
      cert.update!(active: false, demotion_reason: REVOKED_BADGE_REASON, demotion_staff: staff)
    end
  end

  def restore_badge
    revoked_badges.find_each do |cert|
      cert.update!(active: true, demotion_reason: nil, demotion_staff: nil)
    end
  end

  def other_awarded_items
    OrderItem.awarded.joins(:order).where(
      proficient_project_id: proficient_project_id,
      orders: { user_id: order.user_id }
    ).where.not(id: id)
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
