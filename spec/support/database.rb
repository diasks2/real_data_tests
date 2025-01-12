require 'active_record'

ActiveRecord::Base.establish_connection(
  adapter: 'postgresql',
  database: 'real_data_tests_test',
  host: 'localhost'
)