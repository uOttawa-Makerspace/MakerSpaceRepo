# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/locker_mailer
class LockerMailerPreview < ActionMailer::Preview
  def locker_assigned
    locker_rental = find_or_create_locker_rental_with_locker
    LockerMailer.with(locker_rental: locker_rental).locker_assigned
  end

  def locker_checkout
    locker_rental = find_or_create_locker_rental_with_locker
    LockerMailer.with(locker_rental: locker_rental).locker_checkout
  end

  def locker_cancelled
    locker_rental = find_or_create_locker_rental_with_locker
    LockerMailer.with(locker_rental: locker_rental).locker_cancelled
  end

  def locker_cancelled_without_locker
    locker_rental = find_or_create_locker_rental_without_locker
    LockerMailer.with(locker_rental: locker_rental).locker_cancelled
  end

  private

  def find_or_create_locker_rental_with_locker
    LockerRental.joins(:locker).first || create_sample_locker_rental(with_locker: true)
  end

  def find_or_create_locker_rental_without_locker
    LockerRental.where(locker_id: nil).first || create_sample_locker_rental(with_locker: false)
  end

  def create_sample_locker_rental(with_locker: true)
    user = User.first || User.create!(
      name: "Test User",
      email: "test@example.com",
      username: "testuser",
      password: "password123"
    )

    locker = nil
    if with_locker
      locker = Locker.first || Locker.create!(
        specifier: "A-101"
      )
    end

    LockerRental.create!(
      rented_by: user,
      locker: locker
    )
  end
end