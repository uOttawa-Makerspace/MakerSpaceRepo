class AnnouncementDismiss < ApplicationRecord
  belongs_to :user
  belongs_to :announcement

  # Records that the user dismissed the announcement; dismissing again changes nothing.
  # The unique index settles two requests racing: the loser finds the winner's row.
  def self.dismiss(announcement, by:)
    find_or_create_by!(announcement: announcement, user: by)
  rescue ActiveRecord::RecordNotUnique
    find_by!(announcement: announcement, user: by)
  end
end
