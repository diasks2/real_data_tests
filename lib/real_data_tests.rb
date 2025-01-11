# frozen_string_literal: true

require 'real_data_tests/configuration'
require 'real_data_tests/data_anonymizer'
require 'real_data_tests/engine' if defined?(Rails)
require 'real_data_tests/pg_dump_generator'
require 'real_data_tests/record_collector'
require 'real_data_tests/rspec_helper'
require 'real_data_tests/test_data_builder'
require 'real_data_tests/version'

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