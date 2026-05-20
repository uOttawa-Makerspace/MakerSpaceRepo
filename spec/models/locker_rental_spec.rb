require "rails_helper"

RSpec.describe LockerRental, type: :model do
  describe '#renewable?' do
    it 'is true for expired active rentals' do
      rental = build(:locker_rental, :active, owned_until: 1.week.ago)
      expect(rental.renewable?).to be true
    end

    it 'is false for active rentals that are not expired' do
      rental = build(:locker_rental, :active, owned_until: 1.week.from_now)
      expect(rental.renewable?).to be false
    end

    it 'is false for await_payment rentals' do
      rental = build(:locker_rental, :await_payment, owned_until: 1.week.ago)
      expect(rental.renewable?).to be false
    end
  end
end
