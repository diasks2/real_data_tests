# frozen_string_literal: true

require 'real_data_tests/configuration'
require 'real_data_tests/data_anonymizer'
require 'real_data_tests/pg_dump_generator'
require 'real_data_tests/record_collector'
require 'real_data_tests/rspec_helper'
require 'real_data_tests/test_data_builder'
require 'real_data_tests/version'
require 'real_data_tests/railtie' if defined?(Rails)

module RealDataTests
  class Error < StandardError; end

  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration) if block_given?
  end

  def self.create_dump_file(record, name: nil)
    TestDataBuilder.new(record, name: name).create_dump_file
  end
end