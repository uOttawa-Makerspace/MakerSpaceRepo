class ProficientProject < ActiveRecord::Base
  include Filterable
  validates :title,  presence: { message: "A title is required."}, uniqueness: { message: "Title already exists"}
  before_save :capitalize_title
  has_and_belongs_to_many :users
  belongs_to :training
  belongs_to :badge_template
  has_many :photos,                     dependent: :destroy
  has_many :repo_files,                 dependent: :destroy
  has_many :videos,                     dependent: :destroy
  has_many :project_requirements,       dependent: :destroy
  has_many :required_projects, through: :project_requirements
  has_many :inverse_project_requirements, class_name: "ProjectRequirement", foreign_key: "required_project_id"
  has_many :inverse_required_projects, through: :inverse_project_requirements, source: :proficient_project
  has_many :cc_moneys,                  dependent: :destroy
  has_many :order_items,                dependent: :destroy
  has_many :badge_requirements,         dependent: :destroy

  scope :filter_by_level, -> (level) { where(level: level) }
  scope :filter_by_proficiency, -> (proficient) { where(proficient: proficient) }

  def capitalize_title
    self.title = self.title.capitalize
  end

  def self.filter_by_attribute(attribute, value)
    if attribute == "level"
      self.filter_by_level(value)
    elsif attribute == "category"
      joins(:training).where(trainings: {name: value})
    elsif attribute == "search"
      where("LOWER(title) like LOWER(?) OR
                 LOWER(level) like LOWER(?) OR
                 LOWER(description) like LOWER(?)", "%#{value}%", "%#{value}%", "%#{value}%")
    elsif attribute == 'proficiency'
      self.filter_by_proficiency(value)
    else
      self
    end
  end

  def delete_all_badge_requirements
    self.badge_requirements.destroy_all
  end

  def create_badge_requirements(badge_requirements_id)
    badge_requirements_id.each do |requirement_id|
      badge_template = BadgeTemplate.find_by_id(requirement_id)
      self.badge_requirements.create(badge_template: badge_template) if badge_template
    end
  end
end
