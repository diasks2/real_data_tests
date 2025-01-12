# frozen_string_literal: true

require 'rails'
require_relative 'real_data_tests/version'
require_relative 'real_data_tests/configuration'
require_relative 'real_data_tests/data_anonymizer'
require_relative 'real_data_tests/engine' if defined?(Rails)
require_relative 'real_data_tests/pg_dump_generator'
require_relative 'real_data_tests/record_collector'
require_relative 'real_data_tests/rspec_helper'
require_relative 'real_data_tests/test_data_builder'

module RealDataTests
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class DumpFileError < Error; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def use_preset(name)
      configuration.use_preset(name)
    end

    def with_preset(name)
      previous_preset = configuration.current_preset
      configuration.use_preset(name)
      yield if block_given?
    ensure
      configuration.current_preset = previous_preset
    end

    def create_dump_file(record, name: nil)
      raise ConfigurationError, "Configuration not initialized" unless @configuration

      begin
        TestDataBuilder.new(record, name: name).create_dump_file
      rescue => e
        raise DumpFileError, "Failed to create dump file: #{e.message}"
      end
    end

    def root
      File.expand_path('../..', __FILE__)
    end

    def env
      @env ||= (ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development')
    end
  end
end