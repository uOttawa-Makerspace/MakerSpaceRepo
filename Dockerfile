# syntax = docker/dockerfile:1
ARG RUBY_VERSION=4.0.6
FROM ruby:${RUBY_VERSION}-alpine3.24 AS base

WORKDIR /rails

# RUNTIME DEPENDENCIES ONLY
RUN apk add --no-cache \
    bash \
    curl \
    jemalloc \
    libpq \
    tzdata \
    vips \
    yaml && \
    ln -s /bin/grep /usr/bin/grep

# Alpine non-root user setup
RUN addgroup -g 1000 -S rails && \
    adduser -u 1000 -S -G rails -h /rails -s /bin/sh rails

# Runtime environment flags
ENV RAILS_ENV="staging" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test:deploy" \
    LD_PRELOAD="/usr/lib/libjemalloc.so.2" \
    RUBYOPT="--yjit" \
    HUSKY="0" \
    PATH="/rails/bin:${PATH}"

# ----------------- BUILD STAGE -----------------
FROM base AS build

# BUILD TOOLS
RUN --mount=type=cache,target=/var/cache/apk \
    apk add \
    build-base \
    ca-certificates \
    git \
    libpq-dev \
    nodejs \
    openssl \
    openssl-dev \
    pkgconfig \
    vips-dev \
    yaml-dev \
    yarn

# Install Gems & Safe Stripping
COPY Gemfile Gemfile.lock ./
RUN --mount=type=cache,target=/usr/local/bundle/cache \
    --mount=type=cache,target=/root/.bundle \
    bundle config set clean true && \
    bundle install && \
    rm -rf "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    rm -rf "${BUNDLE_PATH}"/ruby/*/cache/*.gem && \
    find "${BUNDLE_PATH}"/ruby/*/gems/ -name "*.so" -exec strip -s {} + 2>/dev/null || true && \
    find "${BUNDLE_PATH}"/ruby/*/gems/ -mindepth 2 -maxdepth 2 -type d \( -name "spec" -o -name "test" -o -name "tests" -o -name "doc" -o -name "examples" -o -name "benchmark" -o -name "fixtures" \) -exec rm -rf {} + && \
    find "${BUNDLE_PATH}"/ruby/*/gems/ \( -name "*.c" -o -name "*.o" -o -name "*.h" -o -name "*.rdoc" -o -name "*.md" -o -name "CHANGELOG*" -o -name "README*" \) -delete

# Install JS Packages
COPY package.json yarn.lock ./
RUN --mount=type=cache,target=/root/.cache/yarn \
    yarn install --frozen-lockfile --ignore-scripts

# Copy Application Code
COPY . .

# Generate dummy SAML certs for asset precompilation
RUN mkdir -p certs && \
    openssl req -x509 -newkey rsa:2048 -keyout certs/saml.key -out certs/saml.crt \
      -days 1 -nodes -subj "/CN=build"

# Precompile Bootsnap cache
RUN bundle exec bootsnap precompile app/ lib/

# Precompile Assets (Propshaft + Vite)
RUN --mount=type=cache,target=/rails/tmp/cache/assets \
    SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

# Ensure runtime directories exist in build stage
RUN mkdir -p certs db log storage tmp

# Delete build artifacts, node_modules, and dummy certs
RUN rm -rf node_modules \
           package.json \
           yarn.lock \
           .yarn \
           certs/* \
           public/vite-dev \
           public/vite-test && \
    find tmp/cache/ -mindepth 1 -maxdepth 1 ! -name 'bootsnap*' -exec rm -rf {} + && \
    find public/ -name "*.map" -type f -delete

# ----------------- FINAL RUNTIME STAGE -----------------
FROM base

# Copy gems and application
COPY --from=build --chown=rails:rails "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build --chown=rails:rails /rails /rails

USER rails:rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]