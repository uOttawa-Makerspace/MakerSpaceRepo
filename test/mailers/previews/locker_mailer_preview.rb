# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/locker_mailer
class LockerMailerPreview < ActionMailer::Preview
  def locker_requested_as_student
    locker_rental = find_or_create_locker_rental_without_locker(as_student: true)
    LockerMailer.with(locker_rental: locker_rental).locker_requested
  end

  def locker_requested_as_general
    locker_rental = find_or_create_locker_rental_with_locker(as_student: false)
    LockerMailer.with(locker_rental: locker_rental).locker_requested
  end

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

  def find_or_create_locker_rental_with_locker(as_student: false)
    LockerRental
      .joins(:locker)
      .where(requested_as: ('student' if as_student))
      .first || create_sample_locker_rental(with_locker: true, as_student:)
  end

  def find_or_create_locker_rental_without_locker(as_student: false)
    LockerRental.where(
      locker_id: nil,
      requested_as: ('student' if as_student)
    ).first || create_sample_locker_rental(with_locker: false, as_student:)
  end

  def create_sample_locker_rental(with_locker: true, as_student: false)
    user =
      User.first ||
        User.create!(
          name: 'Test User',
          email: 'test@example.com',
          username: 'testuser',
          password: 'password123'
        )

    locker = nil
    locker = Locker.first || Locker.create!(specifier: 'A-101') if with_locker

    LockerRental.create!(
      rented_by: user,
      locker: locker,
      requested_as: ('student' if as_student),
      section_name: ('C03' if as_student),
      team_name: ('makerepo team' if as_student)
    )
  end
end
