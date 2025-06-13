# frozen_string_literal: true

namespace :add_badges_to_beginner_trainings do
  desc "Add badges to beginner trainings from September 1st 2022 to now"
  task run: :environment do
    training_sessions_ids =
      TrainingSession.where(
        created_at:
          DateTime.new(2022, 9, 1).beginning_of_day..DateTime.now.end_of_day,
        level: "Beginner"
      ).pluck(:id)
    updated_certifications = []
    no_template_certifications = []
    failed_certifications = []

    Certification
      .where(training_session_id: training_sessions_ids)
      .each do |c|
        badge_template = BadgeTemplate.find_by(training_id: c.training.id)

        if badge_template.present?
          response =
            Badge.acclaim_api_create_badge(
              c.user,
              badge_template.acclaim_template_id
            )
          if response.status == 201
            b =
              Badge.create(
                user_id: c.user.id,
                issued_to: c.user.name,
                acclaim_badge_id: JSON.parse(response.body)["data"]["id"],
                badge_template_id: badge_template.id
              )
            if b.present?
              updated_certifications << "#{c.user.name} - #{badge_template.badge_name} (#{b.acclaim_badge_id})"
            else
              failed_certifications << "#{c.user.name} - #{badge_template.badge_name}"
            end
          else
            failed_certifications << "#{c.user.name} - #{badge_template.badge_name}"
          end
        else
          no_template_certifications << "#{c.user.name} - #{c.training.name_en}"
        end
      end

    puts("\e[32mThese Certifications have been assigned to a Badge\e[0m")
    puts(
      (
        updated_certifications.presence || "No successfully Added Badges"
      )
    )

    puts("\e[33mThese Certifications don't have a related Badge Template\e[0m")
    puts(
      (
        no_template_certifications.presence || "No Certifications without related Badge Templates"
      )
    )

    puts("\e[31mThese Certifications have NOT been assigned to a Badge\e[0m")
    puts(
      (
        failed_certifications.presence || "No Failed Badges"
      )
    )
  end
end
