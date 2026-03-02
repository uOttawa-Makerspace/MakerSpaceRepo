# Help class that is used to host images and show them elsewhere. This is not backed by a table, do not attempt to
class Help < ApplicationRecord
  has_rich_text :comments

  attr_accessor :name, :email, :content, :subject

  validates :gh_issue_number,
            presence: true,
            numericality: {
              only_integer: true
            }
  validates :name, presence: true, length: { minimum: 2 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :subject, presence: true, length: { minimum: 10 }
  # I'd add a length check to comments but this would count HTML characters too
  validates :comments, presence: true

  before_create :send_github_issue

  def send_github_issue
    self.gh_issue_number =
      GithubIssuesService.new.create_issue(
        reporter: name,
        title: subject,
        body: comments
      )
    unless self.gh_issue_number
      errors.add(:base, 'Internal error while submitting issue.')
      throw :abort
    end
  end
end
