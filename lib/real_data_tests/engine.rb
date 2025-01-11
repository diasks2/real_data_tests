require 'rails'

module RealDataTests
  class Engine < ::Rails::Engine
    isolate_namespace RealDataTests

    config.before_configuration do
      RealDataTests.configuration
    end

    initializer 'real_data_tests.initialize' do |app|
      if RealDataTests.configuration
        RealDataTests.configuration.process_delayed_anonymizations
      end
    end
  end
end