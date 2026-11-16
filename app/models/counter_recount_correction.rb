# frozen_string_literal: true

# The record of one counter that CounterRecount changed: the value it had and the value written. Only ever added to.
class CounterRecountCorrection < ApplicationRecord
  def readonly? = persisted? || super
end
