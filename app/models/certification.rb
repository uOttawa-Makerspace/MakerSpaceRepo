# frozen_string_literal: true

class Certification < ApplicationRecord
  # A certification belongs to its user even after the account was soft-deleted: the history stays complete.
  belongs_to :user, -> { including_deleted }, class_name: "User", optional: true
  belongs_to :demotion_staff, -> { including_deleted }, class_name: "User", optional: true
  belongs_to :training_session, optional: true
  has_one :proficient_project_session
  has_one :space, through: :training_session
  has_one :training, through: :training_session
  has_one :proficient_project, through: :proficient_project_session

  validates :user, presence: true
  # The random token in the public badge link; set once at creation and never changed.
  attr_readonly :share_token
  before_validation :assign_share_token, on: :create
  validates :share_token, presence: true, on: :create

  validates :level, inclusion: { in: %w[Beginner Intermediate Advanced] }

  default_scope -> { where(active: true) }
  scope :between_dates_picked,
        ->(start_date, end_date) {unscoped.
          where("created_at BETWEEN ? AND ? ", start_date, end_date)
        }
  scope :inactive, -> { unscoped.where(active: false) }

  # The reason recorded when revoking a project badge deactivates the certification it granted.
  BADGE_REVOKED_REASON = "Project badge revoked"

  # The reason recorded when a trainer drops a trainee from a session or revokes the session's certification.
  TRAINER_REMOVED_REASON = "Removed by the trainer"

  # Takes the certification out of use without deleting it, recording who did it and why; the row
  # and its history stay. Deactivated certifications are left out of every default query.
  def deactivate(staff, reason = TRAINER_REMOVED_REASON)
    update(active: false, demotion_reason: reason, demotion_staff: staff)
  end

  # Whether an active certification of the same user, training and level already exists, so
  # restoring this deactivated one would leave the user holding the same certification twice.
  def duplicate_held?
    return false if active

    training_id = training_session&.training_id || proficient_project_session&.proficient_project&.training_id
    training_id.present? && Certification.held_by(user_id, training_id, level).exists?
  end

  # Every certification (active or not) a user earned through approvals of a proficient project.
  # The project session carries no link to the order item, so user and project identify it.
  def self.for_project(user_id, project_id)
    unscoped.where(
      user_id: user_id,
      id: ProficientProjectSession.where(proficient_project_id: project_id).select(:certification_id)
    )
  end

  # Inactive certifications that a badge revoke deactivated (not ones demoted by hand), the most
  # recently deactivated first. Call on a relation from .for_project.
  def self.revoked_badges
    where(active: false, demotion_reason: BADGE_REVOKED_REASON).order(updated_at: :desc, id: :desc)
  end

  # A badge page is addressed by its share token, or by the numeric id older links use.
  # Tokens always contain a non-digit, so an all-digit key is an id.
  def self.find_for_badge_page!(key)
    key = key.to_s
    key.match?(/\A\d+\z/) ? find(key) : find_by!(share_token: key)
  end

  def self.generate_share_token
    loop do
      token = SecureRandom.urlsafe_base64(16)
      return token if token.match?(/\D/)
    end
  end

  # What a badge link carries: the token (the id only for a row that has none yet).
  def badge_param
    share_token.presence || id
  end

  ##
  # manually finds the training associated with this certification. If you know an easier way of doing this using active
  # record associations, please fix this.
  def training
    if training_session.nil?
      proficient_project_session.proficient_project.training
    else
      training_session.training
    end
  end

  ##
  # manually finds the trainer associated with this certification. If you know an easier way of doing this using active
  # record associations, please fix this.
  def trainer
    if training_session.nil?
      proficient_project_session.user
    else
      training_session.user
    end
  end

  def self.to_csv(attributes)
    CSV.generate { |csv| attributes.each { |row| csv << row } }
  end

  # Active certifications a user holds for a training at a level, whichever way
  # they were earned (a training session or a proficient project).
  def self.held_by(user_id, training_id, level)
    left_joins(:training_session, proficient_project_session: :proficient_project)
      .where(user_id: user_id, level: level)
      .where(
        "training_sessions.training_id = :training_id OR proficient_projects.training_id = :training_id",
        training_id: training_id
      )
  end

  def self.certify_user(training_session_id, user_id, level)
    training_id = TrainingSession.where(id: training_session_id).pick(:training_id)
    if training_id
      existing = held_by(user_id, training_id, level).first
      return existing if existing
    end
    create(user_id:, training_session_id:, level:)
  end

  def assign_share_token
    self.share_token = self.class.generate_share_token if share_token.blank?
  end

  def get_badge_path
    case training_session&.level
    when "Beginner"
      "images/badges/bronze.png"
    when "Intermediate"
      "images/badges/silver.png"
    when "Advanced"
      "images/badges/golden.png"
    else
      "images/badges/none.png"
    end
  end

  def self.highest_certifications(user_id)
    # training_ids = joins(:training).pluck(:training_id)
    # trainings = Training.where(id: training_ids)
    trainings = []
    user = User.including_deleted.find(user_id)
    user_certs = user.certifications
    user_certs.each do |cert|
      trainings << cert.training unless trainings.include? cert.training
    end
    certs = []
    trainings.each do |training|
      certs << certification_highest_level(training.id, user_id)
    end
    certs
  end

  def self.certification_highest_level(training_id, user_id)
    user = User.including_deleted.find(user_id)
    training_certs = []
    user.certifications.each do |cert|
      training_certs << cert if cert.training.id == training_id
    end
    
    highest_cert = training_certs.first
    training_certs.each do |cert|
      highest_cert = cert if highest_cert.level == "Beginner" && cert.level == "Intermediate"
      highest_cert = cert if cert.level == "Advanced"
    end
    highest_cert
  end

  def self.filter_by_attribute(value)
    if value.present?
      inactive.joins(:user, :training).where(
        "LOWER(demotion_reason) like LOWER(:value) OR
                       LOWER(users.name) like LOWER(:value) OR
                       LOWER(trainings.name_en) like LOWER(:value) OR
                       LOWER(trainings.name_fr) like LOWER(:value)",
        { value: "%#{value}%" }
      )
    else
      inactive
    end
  end

  def self.existent_certification(user, training, level)
    user_certs = user.certifications
    user_certs.each do |cert|
      if (cert.training.id == training.id) &&
           (cert.training_session.level == level)
        return cert
      end
    end
    false
  end

  LEVELS = %w[Beginner Intermediate Advanced].freeze

  # Certifications with their training known in SQL, whether earned in a training session or
  # through a proficient project.
  scope :with_training,
        -> do
          left_joins(:training_session, proficient_project_session: :proficient_project).joins(
            "INNER JOIN trainings ON trainings.id = " \
              "COALESCE(training_sessions.training_id, proficient_projects.training_id)"
          )
        end

  # The top-level certifications of each training (all of them when several share that level),
  # whether earned in a training session or through a proficient project. A certification
  # whose training cannot be found is left out.
  def self.highest_level
    certs = all.to_a
    preload_trainings(certs)
    by_training = certs.select(&:training_known?).group_by(&:training)
    by_training.reject { |training, _| training.nil? }.flat_map { |_, held| top_ranked(held) }
  end

  def self.top_ranked(held)
    ranks = held.map(&:rank)
    top = ranks.compact.max
    top ? held.select { |c| c.rank == top } : []
  end
  private_class_method :top_ranked

  # Loads the training of each certification, through its session or its proficient project.
  def self.preload_trainings(certs)
    by_session, by_project = certs.partition(&:training_session_id)
    ActiveRecord::Associations::Preloader.new(records: by_session, associations: { training_session: :training }).call
    ActiveRecord::Associations::Preloader.new(
      records: by_project,
      associations: [:training_session, { proficient_project_session: { proficient_project: :training } }]
    ).call
  end

  # A session certification ranks by its session's level, a project-only one by its own level.
  # A level outside Beginner, Intermediate and Advanced has no rank.
  def rank
    LEVELS.index(training_session_id ? training_session.level : level)
  end

  def training_known?
    training_session_id.present? || proficient_project_session&.proficient_project.present?
  end

  # The name of the training behind the certification, in the current language.
  def name
    training.localized_name
  end

  def get_name_en
    if training_session.nil?
      proficient_project_session.proficient_project.training.name_en
    else
      training_session.training.name_en
    end
  end

  def get_name_fr
    if training_session.nil?
      proficient_project_session.proficient_project.training.name_fr
    else
      training_session.training.name_fr
    end
  end

  def get_skill_id
    if training_session.nil?
      proficient_project_session.proficient_project.training.skill_id
    else
      training_session.training.skill_id
    end
  end
end
