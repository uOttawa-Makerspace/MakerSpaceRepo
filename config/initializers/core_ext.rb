# frozen_string_literal: true

Dir[File.join(Rails.root, 'lib', 'core_ext', '*.rb')].sort.each { |l| require l }
