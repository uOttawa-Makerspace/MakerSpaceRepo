# frozen_string_literal: true

RSpec::Matchers.define_negated_matcher :not_change, :change
RSpec::Matchers.define_negated_matcher :not_have_broadcasted_to, :have_broadcasted_to
RSpec::Matchers.define_negated_matcher :not_have_enqueued_job, :have_enqueued_job
