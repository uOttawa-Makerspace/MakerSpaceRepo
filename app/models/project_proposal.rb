class ProjectProposal < ActiveRecord::Base
  has_many   :categories,     dependent: :destroy
  has_many  :project_joins, dependent: :destroy

  belongs_to  :user

  validates :title,
            format:     { with:    /\A[-a-zA-Z\d\s]*\z/, message: "Invalid project title" },
            presence:   { message: "Project title is required."}

  validates :email,
            presence: { message: "Your email is required." }

  before_save do
    if self.youtube_link && !YoutubeID.from(self.youtube_link)
      self.youtube_link = nil
    end
  end
end
