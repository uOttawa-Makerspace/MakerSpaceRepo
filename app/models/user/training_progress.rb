# frozen_string_literal: true

# What a user has achieved in each training: certified levels, started trainings, awarded
# projects, completed modules and badges. Each is read once per user and kept, so a page listing
# many trainings does not query per training; reload clears them.
module User::TrainingProgress
  extend ActiveSupport::Concern

  TRAINING_LEVELS = %w[Beginner Intermediate Advanced].freeze

  MEMOS = %i[@certified_levels_by_training @started_training_ids @highest_badges @awarded_proficient_project_ids @completed_learning_module_ids].freeze

  def reload(*)
    MEMOS.each { |memo| remove_instance_variable(memo) if instance_variable_defined?(memo) }
    super
  end

  # Every [training_id, level] pair the user holds a certification for.
  def held_training_levels
    certified_levels_by_training.flat_map { |training_id, levels| levels.map { |level| [training_id, level] } }.to_set
  end

  # Ids of the proficient projects the user has been awarded, read once per user.
  def awarded_proficient_project_ids
    @awarded_proficient_project_ids ||= order_items.awarded.pluck(:proficient_project_id)
  end

  # Ids of the learning modules the user has completed, read once per user.
  def completed_learning_module_ids
    @completed_learning_module_ids ||= learning_module_tracks.completed.pluck(:learning_module_id)
  end

  # The levels of the user's certifications earned in a training session, by training id. Read
  # once for all trainings.
  def certified_levels_by_training
    @certified_levels_by_training ||=
      certifications.joins(:training_session).pluck("training_sessions.training_id", "certifications.level")
                    .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end

  # The highest level the user is certified at in the training, or nil.
  def certified_level(training_id)
    held = certified_levels_by_training.fetch(training_id, [])
    TRAINING_LEVELS.reverse.find { |level| held.include?(level) }
  end

  # The ids of the trainings in which the user completed a learning module or was awarded a
  # proficient project. Read once for all trainings.
  def started_training_ids
    @started_training_ids ||=
      (LearningModule.where(id: completed_learning_module_ids).pluck(:training_id) +
        ProficientProject.where(id: awarded_proficient_project_ids).pluck(:training_id)).to_set
  end

  # How far the user is in a training: the highest certified level, else "Newbie" once they have
  # started it, else nil.
  def training_standing(training_id)
    certified_level(training_id) || ("Newbie" if started_training_ids.include?(training_id))
  end

  # The levels whose recommended hours count before moving on: Beginner up to the certified level.
  def recommended_levels(training_id)
    TRAINING_LEVELS.first(TRAINING_LEVELS.index(certified_level(training_id) || "Beginner") + 1)
  end

  # The certification the user's badge for the training shows: the one from a session of the
  # highest level. Read once for all trainings, with each badge's training loaded.
  def highest_badge(training)
    highest_badges[training.id]
  end

  def highest_badges
    @highest_badges ||= begin
      by_training = certifications.joins(:training_session).includes(:training_session).order(:id).group_by { |cert| cert.training_session.training_id }
      badges = by_training.values.filter_map { |certs| highest_session_level_certification(certs) }
      ActiveRecord::Associations::Preloader.new(records: badges.map(&:training_session), associations: :training).call
      badges.index_by { |cert| cert.training_session.training_id }
    end
  end

  private

  # The first certification from a session of the highest level.
  def highest_session_level_certification(certs)
    TRAINING_LEVELS.reverse.each do |level|
      cert = certs.find { |candidate| candidate.training_session.level == level }
      return cert if cert
    end
    nil
  end
end
