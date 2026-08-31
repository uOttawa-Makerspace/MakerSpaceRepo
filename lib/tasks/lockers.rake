# frozen_string_literal: true

namespace :lockers do
  desc 'Check for expired locker rentals, send email notices, and update contacted status'
  task notify_expired_rentals: :environment do
    puts 'Checking for expired locker rentals...'

    # Find active rentals that have passed their owned_until date and haven't been notified yet
    expired_rentals = LockerRental.active
                                  .where.not(owned_until: nil)
                                  .where('owned_until <= ?', Time.current)
                                  .where(notified_of_cancellation_at: nil)

    count = 0
    expired_rentals.find_each do |rental|
      next unless rental.rented_by&.email.present?

      # Send the expiration email notice
      LockerMailer.with(locker_rental: rental).rental_expired.deliver_later

      # Record the notification timestamp and auto-check 'contacted_for_clearance'
      rental.update_columns(
        notified_of_cancellation_at: Time.current,
        contacted_for_clearance: true
      )

      count += 1
      puts "Sent expiration notice for Locker Rental ##{rental.id} (Locker ##{rental.locker&.specifier}) to #{rental.rented_by.email}"
    end

    puts "Done! Notified #{count} expired rental(s)."
  end
end