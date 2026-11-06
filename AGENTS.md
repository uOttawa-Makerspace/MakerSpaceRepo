# AGENTS.md

Instructions for anyone, human or AI agent, changing this repository. MakerRepo is production software used every day by the uOttawa Makerspace: treat every change as one that will touch real users and real data.

## Stack

- Rails 8.1, Ruby 4.0, PostgreSQL 17, Solid Queue (jobs and recurring tasks in `config/recurring.yml`), Solid Cache, Solid Cable.
- Front end: Vite (`vite_ruby`), Stimulus and Turbo, plain JavaScript.
- Tests: RSpec (request, model, job, system specs with Capybara/Selenium), Vitest for JavaScript unit tests.
- Deployed with Docker Compose (`docker-compose.production.yml`): a `web` container and a `worker` container that runs Solid Queue.

## Working environment

- Develop in the devcontainer (`.devcontainer/`); run Ruby, RSpec, Rails and Yarn commands inside it, not on the host.
- Never run commands against the production database. Never point a local tool at production credentials.

## Data safety comes first

- No change may delete or overwrite stored data unless that data is provably redundant and the maintainers approved that specific case.
- Data migrations copy, never move: keep the old column or table, record what changed, and make `down` restore it exactly.
- Rehearse every migration and every data-changing task on a scratch database restored from a recent backup. Compare row counts before and after, and check that `down` restores the data.
- Prefer blocking an action with a clear message (or hiding a row) over destroying it.
- Hard invariants belong in the database: foreign keys, `NOT NULL`, unique indexes, check constraints. A new unique index first checks for existing duplicates and stops with a message instead of removing rows.
- Work that can run twice (jobs, webhooks, rake tasks, form submits) must be safe to run twice: claim the work atomically, use unique keys, and pass a stable idempotency key to external services.

## How to change code

- **Fix the root cause.** No band-aid fixes: no rescue that swallows an error, no retry around a race, no special case for one record, no widened timeout to make a test pass. If the root cause is out of reach, document it instead of hiding it.
- **Pin behaviour before changing it.** Before a fix or refactor, write specs (unit, request or end-to-end, whichever proves it) that pass on the current code. Then change the code against them. A fix comes with the spec that fails without it.
- **Leave the code simpler.** Prefer plain Rails: rich models with clear public methods, small plain Ruby objects under `app/models/` when a model method is not enough. Do not add service, form or presenter layers by default.
- **No side effects in model callbacks**, including `after_commit`. Mail, job enqueues, HTTP calls and writes to other models are called explicitly by the controller, job, webhook or rake task that owns the operation, after its transaction commits. Callbacks may only normalise the record's own attributes.
- **Complexity may not go up.** No method may newly exceed a cyclomatic complexity of 7, and a method already above it may not grow (RuboCop `Metrics/CyclomaticComplexity`, ESLint `complexity`). Extract well-named private methods instead.
- **Coverage may not go down**, for lines or branches, in Ruby or JavaScript. New branches need specs that take them.
- Authorization: Pundit policies, with policy methods delegating to model predicates (for example `rental.editable_by?(user)`).
- Style follows the 37signals conventions (rich models, concerns named for a capability, REST resources for state changes, positive naming), except where this file says otherwise.
- Repeated UI is built as ViewComponents (`app/components/`), each with its Stimulus controller and scoped CSS beside it; one-off markup stays a partial. New JavaScript is Stimulus controllers that touch only their own element: nothing on `window`, no document-wide queries.
- Do not change the request or response contract of `/api/v1` (documented in `doc/api/v1/`) or the endpoints used by the staff app and Design Day without coordinating with those front ends.

## Tests

- Run the whole suite in parallel: `bundle exec rake parallel:setup` once, then `bin/parallel_rspec`. CI runs `CI=1 COVERAGE=1 bin/parallel_rspec`.
- Run targeted specs with `bundle exec rspec <paths>`.
- JavaScript: `yarn test:js`, `yarn lint:js`, `yarn typecheck:js`. ERB: `bin/erb-lint`.
- Security checks CI also runs: `bundle exec brakeman -w2`, `bundle exec bundle-audit check --update`, `bundle exec ruby-audit check`.
- Assert outcomes, not mechanisms: persisted state, rendered content, HTTP status and redirects, and mail by what was delivered (`perform_enqueued_jobs` with `ActionMailer::Base.deliveries`).
- System specs use Capybara's waiting matchers; never `sleep`. Stub external services (Shopify, Google, GitHub) at the boundary.
- Tests must be deterministic: freeze time where dates matter, and never depend on wall-clock speed.

## Documentation

- `doc/flows/` describes each user-facing and background flow. Any change to behaviour, a route, a job, a schedule, a mail or a data path updates the matching page in the same change. A new flow gets a new page, linked from `doc/flows/README.md`.
- `doc/maintenance.md` covers operations (scheduled tasks, backfills, deploy steps). Update it when you change how something is run in production.
- Write docs from the code as it is, in plain neutral English. No personal data in docs, specs or fixtures.

## Commits and pull requests

- One root cause per commit. Commit messages describe behaviour in plain English.
- This repository is public: no internal tracker IDs, no security-sensitive wording that would help an attacker before a fix ships, no secrets, no personal data.
- No AI attribution or co-author trailers in commits or pull request descriptions.
- Hotfixes branch off `staging`. Pull requests target `staging`; maintainers merge.
- Do not add a dependency without the maintainers' approval. Pin exact versions for JavaScript dev tools.
