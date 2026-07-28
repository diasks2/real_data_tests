require 'active_record'

connection_config = {
  adapter: 'postgresql',
  database: ENV.fetch('PGDATABASE', 'real_data_tests_test')
}
connection_config[:host] = ENV['PGHOST'] if ENV['PGHOST']
connection_config[:username] = ENV['PGUSER'] if ENV['PGUSER']
connection_config[:password] = ENV['PGPASSWORD'] if ENV['PGPASSWORD']

ActiveRecord::Base.establish_connection(connection_config)
