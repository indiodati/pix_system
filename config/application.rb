require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "sprockets/railtie"  # <--- Remova ou comente esta linha
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module PixSystem
  class Application < Rails::Application
    config.load_defaults 7.1
    config.time_zone = 'Brasilia'
    config.active_record.default_timezone = :local
    config.i18n.available_locales = [:en, :'pt-BR']
    config.i18n.default_locale = :'pt-BR'
    

    # Nenhuma configuração de assets
  end
end
