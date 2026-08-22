ARG RUBY_VERSION=4.0.5
FROM ruby:$RUBY_VERSION-slim

# Install system dependencies + Node.js 22 LTS + PostgreSQL client + Foreman
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    imagemagick \
    libpq-dev \
    libvips-dev \
    libyaml-dev \
    openssl \
    pkg-config \
    postgresql-client \
    tzdata && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y nodejs && \
    npm install -g yarn && \
    gem install foreman && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

WORKDIR /rails
ENV BUNDLE_PATH="/usr/local/bundle"
ENV PATH="/rails/bin:${PATH}"

CMD ["sleep", "infinity"]