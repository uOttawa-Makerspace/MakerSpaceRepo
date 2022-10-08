# frozen_string_literal: true

namespace :add_badges_to_beginner_trainings do
  desc "Add badges to beginner trainings from September 1st 2022 to now"
  task run: :environment do
    training_sessions_ids =
      Training
        .all
        .where(
          created_at:
            DateTime.new(2022, 9, 1).beginning_of_day..DateTime.now.end_of_day,
          level: "Beginner"
        )
        .pluck(:id)
    updated_certifications = []
    failed_certifications = []

    Certification
      .where(training_session_id: training_sessions_ids)
      .each do |c|
        badge_template = BadgeTemplate.find_by(training_id: c.training.id)

        if badge_template.present?
          response = Badge.acclaim_api_create_badge(c.user, badge_template)
          if response.status == 201
            Badge.create(
              user_id: c.user.id,
              issued_to: c.user.name,
              acclaim_badge_id: JSON.parse(response.body)["data"]["id"],
              badge_template_id: badge_template.id
            )
            updated_certifications << c
          else
            failed_certifications << c
          end
        end
      end

    puts("These certifications have been assigned to a badge")
    puts(updated_certifications)

    puts("These certifications have NOT been assigned to a badge")
    puts(failed_certifications)
  end
end
