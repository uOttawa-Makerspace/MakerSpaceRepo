# CC prices are never negative: a negative proficient_projects.cc or
# coupon_codes.cc_cost made checkout / the coupon claim fail (CcMoney.debit! refuses a negative
# debit). A coupon always has a price (a NULL-price coupon could never be claimed but was
# still offered). The models validate the same; these constraints also hold for update_column /
# update_all / SQL. Adding them fails if a violating row exists: production (2026-08-23 restore)
# has 0 negative cc, 0 negative cc_cost and 0 NULL cc_cost. No backfill. Reversible.
class AddNonNegativePriceChecks < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :proficient_projects, "cc >= 0", name: "proficient_projects_cc_non_negative"
    add_check_constraint :coupon_codes, "cc_cost >= 0", name: "coupon_codes_cc_cost_non_negative"
    change_column_null :coupon_codes, :cc_cost, false
  end
end
