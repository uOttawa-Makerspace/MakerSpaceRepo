# Help class that is used to host images and show them elsewhere. This is not backed by a table, do not attempt to
class Help < ApplicationRecord
  has_rich_text :comments

  attr_accessor :name, :email, :content, :subject

  # Set by the anonymous-capable /api/v1 path: the GitHub issue is public, so the user's text is
  # defanged (no mentions, no cross-references, no raw HTML). Legacy leaves it false and is unchanged.
  attr_accessor :defang_github_text

  ZWJ = "\u200D"

  # Keeps the text readable: a zero-width joiner after @ and # (and GH-) stops GitHub from
  # linking, and < > & are escaped so no raw HTML gets through.
  def self.defang(text)
    text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
        .gsub(/@(?=\w)/, "@#{ZWJ}").gsub(/#(?=\w)/, "##{ZWJ}").gsub(/\bGH-(?=\d)/i) { |m| "#{m}#{ZWJ}" }
  end

  # No need to validate, callback fills this in
  # validates :gh_issue_number,
  #           presence: true,
  #           numericality: {
  #             only_integer: true
  #           }
  validates :name, presence: true, length: { minimum: 2 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :subject, presence: true, length: { minimum: 10 }
  # I'd add a length check to comments but this would count HTML characters too
  validates :comments, presence: true

  # this runs after validation
  before_create :send_github_issue
  
  def send_github_issue
    # create_issue returns false when the GitHub API call fails
    issue = if defang_github_text
              GithubIssuesService.new.create_issue(
                reporter: self.class.defang(name),
                title: self.class.defang(subject),
                body: self.class.defang(comments.to_plain_text)
              )
            else
              GithubIssuesService.new.create_issue(
                reporter: name,
                title: subject,
                body: comments
              )
            end
    self.gh_issue_number = issue ? issue[:number] : nil
    unless self.gh_issue_number
      errors.add(:base, 'Internal error while submitting issue.')
      throw :abort
    end
  end
end
