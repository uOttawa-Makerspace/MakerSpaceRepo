class LearningModule < ApplicationRecord
  include Filterable
  belongs_to :training, optional: true

  # these are conflicting with models with the same name, remove those first
  # before renaming to something more sensible.
  has_many_attached :photos # was: has_many :photos
  has_many_attached :project_files # was: has_many :repo_files
  has_many_attached :videos # was: has_many :videos

  # Normalization runs before validation, but we still want to catch if something breaks
  normalizes :shortcut_name,
             with: ->(shortcut_name) do
               shortcut_name.strip.downcase.underscore.parameterize(
                 separator: '_'
               )
             end
  validates :shortcut_name, format: { with: /\A[a-zA-Z0-9_]+\z/ }, allow_blank: true
  validates :shortcut_name, uniqueness: { case_sensitive: false }

  enum :level,
       {
         # AKA 'no level'
         general: 'General',
         beginner: 'Beginner',
         intermediate: 'Intermediate',
         advanced: 'Advanced'
       },
       validate: true

  # SCORM packages are a zip file
  has_one_attached :scorm_package

  # Check if we need to reprocess package. We need the is_a? check because
  # sometimes no file is uploaded.
  before_save -> do
                new_blob = attachment_changes['scorm_package']
                @scorm_package_changed =
                  new_blob.is_a?(ActiveStorage::Attached::Changes::CreateOne) &&
                    !new_blob.blob.persisted? # Is this really a new package
                @scorm_package_cleared =
                  new_blob.is_a?(ActiveStorage::Attached::Changes::DeleteOne)
              end

  # If scorm package changes, update extraction or purge File is available only
  # after commit, but change key is cleared after save. This would queue the
  # job, and the job is configured to run after commit succeeds
  # https://guides.rubyonrails.org/active_storage_overview.html#downloading-files
  # https://codewithrails.com/blog/rails-enqueue-after-transaction-commit/
  after_save :process_scorm_package,
             if: -> { @scorm_package_changed || @scorm_package_cleared }
  # The unzipped files are attached to this model here. Need to clear if the
  # scorm package changes
  has_many_attached :scorm_package_files

  # Value to receive from the edit form
  attribute :scorm_enabled, :boolean, default: false
  after_initialize -> { self.scorm_enabled = scorm_package.attached? }

  enum :scorm_status,
       { pending: 0, processing: 1, ready: 2, failed: 3 },
       prefix: :scorm

  has_many :learning_module_tracks, dependent: :destroy

  validates :title, presence: { message: 'A title is required.' }
  validate :uniqueness
  before_save :capitalize_title
  before_create :set_order

  scope :filter_by_level, ->(level) { where(level: level) }
  scope :ordered_by_level,
        -> do
          order(
            Arel.sql(
              "CASE level
                WHEN 'general'      THEN 0
                WHEN 'beginner'     THEN 1
                WHEN 'intermediate' THEN 2
                WHEN 'advanced'     THEN 3
                ELSE 0
                END"
            )
          )
        end

  default_scope { order(:order) }

  def scorm_asset_url(relative_path)
    if relative_path.include?('..')
      raise ArgumentError, 'Path traversal detected'
    end

    Rails.application.routes.url_helpers.scorm_asset_learning_area_url(
      self,
      path: relative_path,
      host: Rails.application.credentials.host
    )
  end

  def tracks_for_user(user)
    learning_module_tracks.find_by(user:)
  end

  def capitalize_title
    self.title = title.upcase_first
  end

  def self.filter_by_attribute(attribute, value)
    if attribute == 'level'
      filter_by_level(value)
    elsif attribute == 'category'
      joins(:training).where(trainings: { name: value })
    elsif attribute == 'search'
      sanitized = sanitize_sql_like(value)
      where(
        'LOWER(title) LIKE LOWER(?) OR
        LOWER(level) LIKE LOWER(?) OR
        LOWER(description) LIKE LOWER(?)',
        "%#{sanitized}%",
        "%#{sanitized}%",
        "%#{sanitized}%"
      )
    else
      self
    end
  end

  def extract_urls
    URI.extract(self.description)
  end

  def extract_valid_urls
    extract_urls.uniq.select do |url|
      uri = URI.parse(url)
      uri.host == 'wiki.makerepo.com' ||
        uri.host&.end_with?('.wiki.makerepo.com')
    rescue URI::InvalidURIError
      false
    end
  end

  private

  # Called when scorm package changes
  def process_scorm_package
    if scorm_package.attached?
      Rails.logger.info "Queued SCORM extract for learning module #{id}"
      # ExtractScorm purges files eventually.
      ExtractScormJob.perform_later(id)
    else
      # Package removed, delete files
      scorm_package_files.purge_later
    end
  end

  def uniqueness
    if LearningModule
         .where(title: self.title, training_id: self.training_id)
         .where.not(id: self.id)
         .count > 0
      self.errors.add(:title, 'Title already exists')
    end
  end

  def set_order
    self.order =
      (
        if LearningModule.maximum(:order).present?
          LearningModule.maximum(:order) + 1
        else
          0
        end
      )
  end
end
