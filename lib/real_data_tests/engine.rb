require 'rails'

module RealDataTests
  class Engine < ::Rails::Engine
    isolate_namespace RealDataTests

    config.before_configuration do
      RealDataTests.configuration
    end
  end
end