# syntax = docker/dockerfile:1

ARG RUBY_VERSION=4.0.5
FROM ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Runtime system dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    curl \
    imagemagick \
    libjemalloc2 \
    libpq5 \
    libvips42 \
    openssl \
    tzdata && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

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

# Install build tools + Node.js 22 LTS & Yarn
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    ca-certificates \
    git \
    gnupg \
    libpq-dev \
    libvips-dev \
    libyaml-dev \
    openssl \
    pkg-config && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y nodejs && \
    npm install -g yarn && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Install JS packages
COPY package.json yarn.lock ./
RUN HUSKY=0 yarn install --frozen-lockfile --ignore-scripts

# Copy app code
COPY . .

# Precompile Bootsnap
RUN bundle exec bootsnap precompile app/ lib/

# Generate temporary dummy SAML certs for asset precompilation
RUN mkdir -p certs && \
    openssl req -x509 -newkey rsa:2048 -keyout certs/saml.key -out certs/saml.crt -days 1 -nodes -subj "/CN=build"

# Precompile Assets (Sprockets + Vite)
RUN SECRET_KEY_BASE_DUMMY=1 RAILS_ENV=staging bundle exec rails assets:precompile

# ----------------- FINAL RUNTIME STAGE -----------------
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Clean build-time dummy certs, ensure all runtime directories exist, and configure non-root user
RUN rm -rf certs/* && \
    mkdir -p certs db log storage tmp && \
    groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp certs
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]