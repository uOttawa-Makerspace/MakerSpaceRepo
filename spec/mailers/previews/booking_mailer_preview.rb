# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/booking_mailer
class BookingMailerPreview < ActionMailer::Preview
  def send_booking_needs_approval
    booking = find_or_build_booking
    BookingMailer.send_booking_needs_approval(booking.id)
  end

  def send_booking_automatically_approved
    booking = find_or_build_booking
    BookingMailer.send_booking_automatically_approved(booking.id)
  end

  def send_booking_approved
    booking = find_or_build_booking
    BookingMailer.send_booking_approved(booking.id)
  end

  def send_booking_approval_request_sent
    user_booking_approval = find_or_build_user_booking_approval
    emails = ["admin1@example.com", "admin2@example.com"]
    BookingMailer.send_booking_approval_request_sent(user_booking_approval.id, emails)
  end

  def send_booking_approval_request_approved
    user_booking_approval = find_or_build_user_booking_approval
    BookingMailer.send_booking_approval_request_approved(user_booking_approval.id)
  end

  private

  def find_or_build_booking
    SubSpaceBooking.first || create_sample_booking
  end

  def find_or_build_user_booking_approval
    UserBookingApproval.first || create_sample_user_booking_approval
  end

  def create_sample_booking
    # Find or create necessary associations
    user = User.first || User.create!(
      name: "Test User",
      email: "test@example.com",
      username: "testuser",
      password: "password123"
    )

    space = Space.first || Space.create!(
      name: "Test Space"
    )

    sub_space = SubSpace.first || SubSpace.create!(
      name: "Test Room",
      space: space,
      approval_required: true
    )

    # Create the booking
    SubSpaceBooking.create!(
      user: user,
      sub_space: sub_space,
      name: "Test Booker",
      description: "Team Meeting",
      start_time: 1.day.from_now.beginning_of_hour,
      end_time: 1.day.from_now.beginning_of_hour + 2.hours
    )
  end

  def create_sample_user_booking_approval
    user = User.first || User.create!(
      name: "Test User",
      email: "test@example.com",
      username: "testuser",
      password: "password123"
    )

    UserBookingApproval.create!(
      user: user
    )
  end
end