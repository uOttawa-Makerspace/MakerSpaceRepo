# syntax = docker/dockerfile:1
ARG RUBY_VERSION=4.0.6
FROM ruby:${RUBY_VERSION}-alpine3.24 AS base

WORKDIR /rails

# Install all development tools, compilers, and libraries
RUN apk add --no-cache \
    bash \
    build-base \
    ca-certificates \
    curl \
    git \
    jemalloc \
    libpq \
    openssh-client \
    openssl \
    openssl-dev \
    pkgconfig \
    postgresql-client \
    postgresql-dev \
    tzdata \
    vips \
    vips-dev \
    yaml \
    yaml-dev && \
    ln -s /bin/grep /usr/bin/grep

# Copy Node.js 24 and NPM from official Node Alpine image
COPY --from=node:24-alpine /usr/local/bin/node /usr/local/bin/node
COPY --from=node:24-alpine /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    npm install -g yarn

# Install Foreman for local process management (Procfile.dev)
RUN gem install foreman

# Configure environment
ENV BUNDLE_PATH="/usr/local/bundle" \
    LD_PRELOAD="/usr/lib/libjemalloc.so.2" \
    PATH="/rails/bin:${PATH}" \
    HISTFILE="/rails/tmp/.bash_history"

CMD ["sleep", "infinity"]