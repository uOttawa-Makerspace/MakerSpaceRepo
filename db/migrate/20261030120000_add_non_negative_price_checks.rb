# CC prices are never negative (D-S42 review): a negative proficient_projects.cc or
# coupon_codes.cc_cost made checkout / the coupon claim fail (CcMoney.debit! refuses a negative
# debit). The models validate >= 0 (blank allowed: NULL passes a CHECK); these constraints also
# hold for update_column / update_all / SQL. Adding them fails if a negative row exists, so the
# production data must be checked first (see the slice report). No backfill. Reversible.
class AddNonNegativePriceChecks < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :proficient_projects, "cc >= 0", name: "proficient_projects_cc_non_negative"
    add_check_constraint :coupon_codes, "cc_cost >= 0", name: "coupon_codes_cc_cost_non_negative"
  end
end
