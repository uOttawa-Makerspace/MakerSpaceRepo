# frozen_string_literal: true

# nobspw_rails7 validates every password by spawning `grep` against a
# 100k-line dictionary (NOBSPW_RAILS7::ValidationMethods#shell_grep). Almost every
# factory-built user shares the same password, so the suite paid one process
# spawn per user. The result is a pure function of the password (the dictionary
# never changes), so memoize it per distinct password for the life of the run.
# The real grep still runs once per distinct password; the verdict is unchanged.
module PasswordCheckerShellGrepCache
  CACHE = {}

  private

  def shell_grep
    CACHE.fetch(@password) { CACHE[@password] = super }
  end
end

NOBSPW_RAILS7::PasswordChecker.prepend(PasswordCheckerShellGrepCache)
