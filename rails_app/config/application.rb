require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
# This app's .env lives at the repo root (one directory above this Rails
# app's own root), not dotenv-rails' default Rails.root/.env — so the search
# path has to be redirected before dotenv-rails' `before_configuration` hook
# runs its default load. `defined?` guards this for every environment other
# than development, where dotenv-rails isn't in the Gemfile at all (see
# Gemfile's comment: kept out of :test deliberately, to keep tests hermetic;
# out of :production/:worker images, where real secrets come from
# docker-compose.yml's `environment:` blocks, not a .env file on disk).
Bundler.require(*Rails.groups)
Dotenv::Rails.files = ["../.env"] if defined?(Dotenv::Rails)

module RailsApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
