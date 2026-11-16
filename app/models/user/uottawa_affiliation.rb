# frozen_string_literal: true

# An internal identity (a uOttawa student, faculty or staff member) pays internal prices, so it can
# be chosen only with proof of a uOttawa affiliation: a uOttawa email address (the domain after the
# last "@" is exactly uottawa.ca, in any case; subdomains do not count) that the user has confirmed
# through the emailed link. A new account counts too: it cannot sign in until that link confirms the
# address. An address changes only through a link sent to the new address, so a confirmed account's
# address is its own.
# Every change of identity to an internal one is checked, also from one internal identity to another,
# so existing accounts keep the identity they have.
module User::UottawaAffiliation
  extend ActiveSupport::Concern

  UOTTAWA_EMAIL_DOMAIN = "uottawa.ca"

  included do
    validate :internal_identity_has_proof, if: -> { identity_changed? && internal? }

    # Accounts with an internal identity and no confirmed uOttawa email, for the owner's review.
    scope :internal_without_proof, lambda {
      where(identity: User::INTERNAL_IDENTITIES)
        .where.not(id: where(confirmed: true).where("LOWER(users.email) LIKE ?", "%@#{UOTTAWA_EMAIL_DOMAIN}").select(:id))
    }
  end

  def uottawa_affiliation_proven?
    uottawa_email? && (confirmed? || new_record?)
  end

  private

  def uottawa_email?
    _, at, domain = email.to_s.rpartition("@")
    at.present? && domain.casecmp?(UOTTAWA_EMAIL_DOMAIN)
  end

  def internal_identity_has_proof
    errors.add(:identity, :needs_uottawa_proof) unless uottawa_affiliation_proven?
  end
end
