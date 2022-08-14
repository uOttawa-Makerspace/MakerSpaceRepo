# frozen_string_literal: true

class ProjectProposal < ApplicationRecord
  belongs_to :user
  belongs_to :admin, class_name: "User", foreign_key: "admin_id"
  has_many :categories, dependent: :destroy
  has_many :project_joins, dependent: :destroy
  has_many :repositories
  has_many :photos, dependent: :destroy
  has_many :repo_files, dependent: :destroy
  has_many :project_proposals,
           class_name: "ProjectProposal",
           foreign_key: "linked_project_proposal_id"
  belongs_to :linked_project_proposal,
             class_name: "ProjectProposal",
             foreign_key: "linked_project_proposal_id"

  scope :approved, -> { where(approved: 1) }

  validates :username,
            presence: {
              message: "Veuillez entrer votre nom / Please enter your name."
            }

  validates :title,
            format: {
              with: /\A[-a-zA-ZÀ-ÿ\d\s]*\z/,
              message: "Le titre du projet est invalide / Invalid project title"
            },
            presence: {
              message:
                'Veuillez entrer le titre du projet / Please enter the project\'s title'
            }

  validates :email,
            presence: {
              message:
                "Veuillez entrer votre addresse couriel / Please enter your email address"
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
                "Coût prévu du projet invalide / Estimated cost can not be below 0"
            }

  before_save do
    self.youtube_link = nil if youtube_link && !YoutubeID.from(youtube_link)
  end

  before_create do
    self.slug = title.downcase.gsub(/[^0-9a-z ]/i, "").gsub(/\s+/, "-")
  end

  before_update do
    self.slug =
      id.to_s + "." + title.downcase.gsub(/[^0-9a-z ]/i, "").gsub(/\s+/, "-")
  end

  def self.filter_by_attribute(value)
    if value
      if value == "search="
        default_scoped
      else
        value = value.split("=").last.gsub("+", " ").gsub("%20", " ")
        where(
          "LOWER(users.name) like LOWER(?) OR
               LOWER(users.username) like LOWER(?) OR
               LOWER(client) like LOWER(?) OR
               LOWER(title) like LOWER(?)",
          "%#{value}%",
          "%#{value}%",
          "%#{value}%",
          "%#{value}%"
        )
      end
    else
      default_scoped
    end
  end

  def approval_status
    case self.approved
    when 0
      "No"
    when 1
      "Yes"
    when nil
      "Not validated"
    end
  end
end
