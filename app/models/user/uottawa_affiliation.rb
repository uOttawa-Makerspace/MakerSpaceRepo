# frozen_string_literal: true

# An internal identity (a uOttawa student, faculty or staff member) pays internal prices, so it can
# be chosen only with proof of a uOttawa affiliation. Proof is either:
# - a uOttawa email address (@uottawa.ca) the user has confirmed through the emailed link. A new
#   account counts too: it cannot sign in until that link confirms the address. An address changes
#   only through a link sent to the new address, so a confirmed account's address is its own.
# - a student number uOEng confirmed: the user's uOEng record (written by the membership check)
#   carries the same student number as the account.
# Only a change of identity to an internal one is checked, so existing accounts keep theirs.
module User::UottawaAffiliation
  extend ActiveSupport::Concern

  UOTTAWA_EMAIL_DOMAIN = "@uottawa.ca"

  included do
    validate :internal_identity_has_proof, if: -> { identity_changed? && internal? }

    # Accounts with an internal identity and neither kind of proof, for the owner's review.
    scope :internal_without_proof, lambda {
      where(identity: User::INTERNAL_IDENTITIES)
        .where.not(id: where(confirmed: true).where("LOWER(users.email) LIKE ?", "%#{UOTTAWA_EMAIL_DOMAIN}").select(:id))
        .where.not(id: joins(:uoeng_profile).where("uoeng_profiles.emplid = users.student_id").select(:id))
    }
  end

  def uottawa_affiliation_proven?
    uottawa_email_proven? || student_id_confirmed_by_uoeng?
  end

  private

  def uottawa_email_proven?
    email.to_s.downcase.end_with?(UOTTAWA_EMAIL_DOMAIN) && (confirmed? || new_record?)
  end

  def student_id_confirmed_by_uoeng?
    student_id.present? && uoeng_profile&.emplid == student_id
  end

  def internal_identity_has_proof
    errors.add(:identity, :needs_uottawa_proof) unless uottawa_affiliation_proven?
  end
end
