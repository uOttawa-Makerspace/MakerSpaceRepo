class ProjectProposal < ActiveRecord::Base
  has_many   :categories,     dependent: :destroy
  has_one    :user,  -> {where(role: "regular_user")}
  has_one    :user,  -> {where(role: "admin")}

  validates :title,
            format:     { with:    /\A[-a-zA-Z\d\s]*\z/, message: "Invalid project title" },
            presence:   { message: "Project title is required."}

  validates :email,
            presence: { message: "Your email is required." }
end
