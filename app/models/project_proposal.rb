# frozen_string_literal: true

class ProjectProposal < ApplicationRecord
  include SniffedUploadValidation
  include DisplayUser
  include Categorizable

  belongs_to :user, optional: true
  belongs_to :admin, class_name: 'User', foreign_key: 'admin_id', optional: true
  display_user_for :user, :admin
  has_many :project_joins, dependent: :destroy
  has_many :repositories, dependent: :nullify
  has_many :project_proposals,
           class_name: 'ProjectProposal',
           foreign_key: 'linked_project_proposal_id',
           dependent: :nullify
  belongs_to :linked_project_proposal,
             class_name: 'ProjectProposal',
             foreign_key: 'linked_project_proposal_id',
             optional: true

  # Attachments with carousel thumbnail variants
  has_many_attached :photos do |attachable|
    attachable.variant :explore, resize_to_limit: [210 * 2, 230 * 2]
    attachable.variant :photo_slide, resize_to_limit: [65 * 3, 65]
    attachable.variant :photo_slide_first, resize_to_limit: [500 * 2, 500]
    attachable.variant :repo_display_wrapper, resize_to_fill: [225 * 2, 225 * 2]
  end

  has_many_attached :project_files

  # project files are checked by sniffed content type and size in the model
  # (an invalid file makes the record invalid, so `attach` returns false and nothing is stored;
  # callers that attach one file at a time must check the result - see a9-notes).
  MAX_PROJECT_FILE_SIZE = 100.megabytes
  validates_sniffed_upload :project_files,
                           deny: SniffedUploadValidation::DANGEROUS_FILE_TYPES,
                           max_size: -> { MAX_PROJECT_FILE_SIZE }

  # The scopes are written out below: the generated negative scope for "approved" would clash with the
  # "not_approved" value and Rails warns about it at every boot.
  enum :approved, { not_approved: 0, approved: 1 }, scopes: false
  enum :season, { fall: 0, summer: 1, winter: 2 }

  scope :approved, -> { where(approved: :approved) }
  scope :not_approved, -> { where(approved: :not_approved) }
  scope :for_year, ->(year) { where(year:) }
  scope :for_season, ->(season) { where(season:) }

  # Sort project proposals by semester
  scope :by_semester,
        -> do
          t = ProjectProposal.arel_table
          order(t[:year].desc.nulls_last, t[:season].asc.nulls_last)
        end

  scope :search,
        ->(query) do
          normalized = query&.strip&.downcase
          return all if normalized.blank?

          q = ActiveRecord::Base.connection.quote("%#{normalized}%")
          n = ActiveRecord::Base.connection.quote(normalized)

          where(<<~SQL, term: "%#{normalized}%", normalized: normalized)
            LOWER(title) ILIKE :term
            OR LOWER(client) ILIKE :term
            OR LOWER(description) ILIKE :term
            OR LOWER(username) ILIKE :term
            OR similarity(LOWER(title), :normalized) > 0.15
            OR similarity(LOWER(client), :normalized) > 0.15
            OR similarity(LOWER(description), :normalized) > 0.15
            OR similarity(LOWER(username), :normalized) > 0.15
          SQL
            .order(Arel.sql("LOWER(title)       ILIKE #{q} DESC"))
            .order(Arel.sql("LOWER(client)      ILIKE #{q} DESC"))
            .order(Arel.sql("LOWER(username)    ILIKE #{q} DESC"))
            .order(Arel.sql("LOWER(description) ILIKE #{q} DESC"))
            .order(Arel.sql("similarity(LOWER(title),       #{n}) DESC"))
            .order(Arel.sql("similarity(LOWER(client),      #{n}) DESC"))
            .order(Arel.sql("similarity(LOWER(username),    #{n}) DESC"))
            .order(Arel.sql("similarity(LOWER(description), #{n}) DESC"))
        end

  validates :username,
            presence: {
              message: 'Veuillez entrer votre nom / Please enter your name.'
            }

  validates :title,
            presence: {
              message:
                'Veuillez entrer le titre du projet / Please enter the project\'s title'
            }

  validates :email,
            presence: {
              message:
                'Veuillez entrer votre addresse couriel / Please enter your email address'
            }

  validates :client,
            presence: {
              message:
                'Veuillez entrer le nom du client / Please enter the client\'s name'
            }

  validates :project_cost,
            numericality: {
              greater_than_or_equal_to: 0,
              message:
                'Coût prévu du projet invalide / Estimated cost can not be below 0'
            }

  validate :season_and_year_together, if: -> { season_changed? || year_changed? }

  before_save do
    self.youtube_link = nil if youtube_link && !YoutubeID.from(youtube_link)
  end

  before_create do
    self.slug = title.downcase.gsub(/[^0-9a-z ]/i, '').gsub(/\s+/, '-')
  end

  before_update do
    self.slug = id_slug
  end

  # The stored slug is "<id>.<title>". A new record has no id until its row is inserted, so the create path calls
  # this inside its transaction once the record is saved. An edit already stores it (before_update).
  def store_id_slug!
    update_column(:slug, id_slug) unless slug == id_slug
    true
  end

  def id_slug
    "#{id}.#{title.downcase.gsub(/[^0-9a-z ]/i, '').gsub(/\s+/, '-')}"
  end

  # The leading integer of "12", "12-title" or the old "12.title" form names the proposal.
  def self.find_by_param(param)
    id = param.to_s[/\A\d+(?=[-.]|\z)/]
    find_by(id:) if id
  end

  # "<id>-<title>" is the address of a saved proposal; the id alone when the title has no
  # letters or digits. The saved title is used, so a title typed into a form that was
  # refused does not change the address.
  def to_param
    return unless persisted?

    [id, title_in_database.to_s.parameterize.presence].compact.join('-')
  end

  def active_semester_label
    "#{season.capitalize} #{year}" if season && year
  end

  def clear_semester
    update(season: nil, year: nil)
  end

  def has_user
    !self.user_id.nil?
  end

  def approval_status
    if approved?
      'Yes'
    elsif not_approved?
      'No'
    else
      'Not validated'
    end
  end

  private

  # A semester is a season and a year together. Proposals saved before this rule may hold only one of
  # them; they are checked when either value is changed, so their other edits are not blocked.
  def season_and_year_together
    errors.add(:base, :semester_incomplete) if season.blank? != year.blank?
  end
end
