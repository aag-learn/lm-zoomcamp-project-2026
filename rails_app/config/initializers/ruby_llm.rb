RubyLLM.configure do |config|
  # ENV, not Rails credentials — consistent with how this project sources every
  # other real secret (RAILS_MASTER_KEY, POSTGRES_PASSWORD), and easier for
  # non-developer reviewers to configure via .env. No default: a missing key
  # should fail loudly (ENV.fetch raises KeyError), not silently proceed.
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY")
  # config.default_model = "gpt-5-nano"

  # Use the association-based acts_as API (recommended)
  config.use_new_acts_as = true
end
