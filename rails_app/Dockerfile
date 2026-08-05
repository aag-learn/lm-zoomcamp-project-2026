FROM ruby:4.0-slim AS base

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

FROM base AS web
ENV RAILS_ENV=production
# Precompiling boots the full Rails environment, so every initializer that
# reads a required ENV var (RAILS_MASTER_KEY via SECRET_KEY_BASE_DUMMY,
# OPENAI_API_KEY via config/initializers/ruby_llm.rb) needs a build-time
# stand-in — none of these values need to be real, since precompiling never
# calls the LLM provider or decrypts credentials, it just needs the app to boot.
RUN SECRET_KEY_BASE_DUMMY=1 OPENAI_API_KEY=dummy bin/rails assets:precompile
ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0"]

FROM base AS worker
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
ENV PATH="/root/.local/bin:$PATH"
RUN uv tool install ansible-core
ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/jobs"]
