# frozen_string_literal: true

# The concurrency specs park one thread (holding a row lock) on a Queue while the main thread
# runs the competing request, then release it. Both ends of that hand-off must be bounded:
#   * the main thread waits for the park with `ThreadPause.await`, so a thread that failed before
#     it parked fails the example with a message instead of hanging the worker;
#   * the parked thread waits with `queue.pop(timeout: ThreadPause::PARKED_TIMEOUT)`, so a main
#     thread that raised before releasing it cannot leave the thread (and its row lock) parked for
#     good, which would make the example's own cleanup wait on that lock forever.
module ThreadPause
  AWAIT_TIMEOUT = 15
  PARKED_TIMEOUT = 30

  def self.await(queue, what = "the parked thread")
    queue.pop(timeout: AWAIT_TIMEOUT) || raise("#{what} did not signal within #{AWAIT_TIMEOUT}s")
  end
end
