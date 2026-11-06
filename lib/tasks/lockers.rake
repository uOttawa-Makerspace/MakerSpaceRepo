# frozen_string_literal: true

namespace :lockers do
  desc 'Mail the renters of rentals that expired in the last LockerRental::EXPIRY_NOTICE_WINDOW and mark them notified'
  task notify_expired_rentals: :environment do
    puts 'Checking for expired locker rentals...'
    count = LockerRental.notify_expired_rentals!(log: method(:puts))
    puts "Done! Notified #{count} expired rental(s)."
  end
end
