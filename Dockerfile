# syntax = docker/dockerfile:1

ARG RUBY_VERSION=4.0.5
FROM ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Runtime system dependencies + BuildKit apt cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    curl imagemagick libjemalloc2 libpq5 libvips42 openssl tzdata && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Performance & environment flags
ENV RAILS_ENV="staging" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="libjemalloc.so.2" \
    RUBYOPT="--yjit" \
    HUSKY="0"

# ----------------- BUILD STAGE -----------------
FROM base AS build

# Copy Node.js and NPM from official Node 24 image (skips slow apt repo config & download)
COPY --from=node:24-bookworm-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=node:24-bookworm-slim /usr/local/lib/node_modules /usr/local/lib/node_modules

# Recreate npm/npx symlinks and install Yarn globally
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    npm install -g yarn

# Install build tools + BuildKit apt cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential ca-certificates git libpq-dev libvips-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Install gems + BuildKit bundle cache
COPY Gemfile Gemfile.lock ./
RUN --mount=type=cache,target=/usr/local/bundle/cache \
    --mount=type=cache,target=/root/.bundle \
    bundle install && \
    rm -rf "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Install JS packages + BuildKit yarn cache
COPY package.json yarn.lock ./
RUN --mount=type=cache,target=/usr/local/share/.cache/yarn \
    HUSKY=0 yarn install --frozen-lockfile --ignore-scripts

# Copy app code
COPY . .

# Generate temporary dummy SAML certs for asset precompilation
RUN mkdir -p certs && \
    openssl req -x509 -newkey rsa:2048 -keyout certs/saml.key -out certs/saml.crt -days 1 -nodes -subj "/CN=build"

# Precompile Bootsnap
RUN bundle exec bootsnap precompile app/ lib/

# Precompile Assets (Sprockets + Vite) + BuildKit assets cache
RUN --mount=type=cache,target=/rails/tmp/cache/assets \
    SECRET_KEY_BASE_DUMMY=1 RAILS_ENV=staging bundle exec rails assets:precompile

# Strip node_modules to prevent bloating the final runtime image (~400MB saved)
RUN rm -rf node_modules

# ----------------- FINAL RUNTIME STAGE -----------------
FROM base

# Copy app and bundle with correct ownership directly (avoids double-layering from chown)
COPY --from=build --chown=1000:1000 "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build --chown=1000:1000 /rails /rails

# Ensure all runtime directories exist, and configure non-root user
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p certs db log storage tmp && \
    chown -R rails:rails db log storage tmp certs

USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]