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

  # Opens the GitHub issue for a saved report and stores its number. Returns true on success.
  # When GitHub does not answer with an issue number the report stays saved without a number,
  # the error is added to the record and false is returned. Called by whoever saved the record,
  # after the save.
  def file_issue
    issue = GithubIssuesService.new.create_issue(**issue_fields)
    number = issue && issue[:number]
    return update!(gh_issue_number: number) if number

    errors.add(:base, :issue_submission_failed)
    false
  end

  private

  # The GitHub issue is public: the anonymous-capable paths defang the user's text.
  def issue_fields
    if defang_github_text
      { reporter: self.class.defang(name), title: self.class.defang(subject),
        body: self.class.defang(comments.to_plain_text) }
    else
      { reporter: name, title: subject, body: comments }
    end
  end
end
