class LearningModule < ApplicationRecord
  include Filterable
  belongs_to :training
  has_many :photos,                     dependent: :destroy
  has_many :repo_files,                 dependent: :destroy
  has_many :videos,                     dependent: :destroy
  has_many :learning_module_tracks,     dependent: :destroy

  validates :title, presence: { message: 'A title is required.' }
  validate :uniqueness
  before_save :capitalize_title

  scope :filter_by_level, ->(level) { where(level: level) }

  def capitalize_title
    self.title = title.upcase_first
  end

  def self.filter_by_attribute(attribute, value)
    if attribute == 'level'
      filter_by_level(value)
    elsif attribute == 'category'
      joins(:training).where(trainings: { name: value })
    elsif attribute == 'search'
      where("LOWER(title) like LOWER(?) OR
                 LOWER(level) like LOWER(?) OR
                 LOWER(description) like LOWER(?)", "%#{value}%", "%#{value}%", "%#{value}%")
    else
      self
    end
  end

  def extract_urls
    URI.extract(self.description)
  end

  def extract_valid_urls
    self.extract_urls.uniq.select{ |url| url.include?("wiki.makerepo.com") }
  end

  private

  def uniqueness
    if LearningModule.where(title: self.title, training_id: self.training_id).where.not(id: self.id).count > 0
      self.errors.add(:title, "Title already exists")
    end
  end

end
