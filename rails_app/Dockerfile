FROM ruby:4.0-slim AS base

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

FROM base AS web
CMD ["bin/rails", "server", "-b", "0.0.0.0"]

FROM base AS worker
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
ENV PATH="/root/.local/bin:$PATH"
RUN uv tool install ansible-core
CMD ["bin/jobs"]
