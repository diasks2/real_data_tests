module RealDataTests
  class Railtie < Rails::Railtie
    config.after_initialize do
      RealDataTests.configuration.process_delayed_anonymizations
    end
  end
end