# frozen_string_literal: true
ENV['RAILS_ENV'] = 'test'

require 'rails'
require 'active_record'
require 'real_data_tests'
require 'database_cleaner/active_record'
require 'support/database'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    # Make sure connection is established before setting up DatabaseCleaner
    begin
      ActiveRecord::Base.connection
    rescue ActiveRecord::NoDatabaseError
      system('createdb real_data_tests_test')
      ActiveRecord::Base.establish_connection(
        adapter: 'postgresql',
        database: 'real_data_tests_test',
        host: 'localhost'
      )
    end

    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
