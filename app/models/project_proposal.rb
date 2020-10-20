# frozen_string_literal: true

class ProjectProposal < ApplicationRecord
  belongs_to :user
  belongs_to :admin, class_name: 'User', foreign_key: 'admin_id'
  has_many :categories,     dependent: :destroy
  has_many :project_joins,  dependent: :destroy
  has_many :repositories

  validates :title,
            format: { with: /\A[-a-zA-ZÀ-ÿ\d\s]*\z/, message: 'Invalid project title' },
            presence: { message: 'Project title is required.' }

  validates :email,
            presence: { message: 'Your email is required.' }

  before_save do
    self.youtube_link = nil if youtube_link && !YoutubeID.from(youtube_link)
  end

  scope :approved, -> { where(approved: 1) }

end
