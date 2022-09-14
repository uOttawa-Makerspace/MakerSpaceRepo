class CreateBookingStatuses < ActiveRecord::Migration[6.1]
  def change
    create_table :booking_statuses do |t|
      t.string :name, null: false
      t.text :description
      t.references :booking_status, index: true, foreign_key: true
      t.references :sub_space_booking, index: true, foreign_key: true
      t.timestamps
    end

    reversible do |change|
      change.up do
        BookingStatus.create(
          name: "Pending",
          description: "The booking is pending staff review."
        )
        BookingStatus.create(
          name: "Approved",
          description: "The booking has been approved."
        )
        BookingStatus.create(
          name: "Declined",
          description: "The booking has been declined."
        )
      end
    end
  end
end
