module RealDataTests
  module RSpecHelper
    def load_real_test_data(name)
      dump_path = File.join(RealDataTests.configuration.dump_path, "#{name}.sql")
      raise Error, "Test data file not found: #{dump_path}" unless File.exist?(dump_path)

      # First, disable foreign key constraints
      ActiveRecord::Base.connection.execute('SET CONSTRAINTS ALL DEFERRED;')

      # Load the SQL dump
      result = system("psql #{connection_options} < #{dump_path}")

      # Re-enable foreign key constraints
      ActiveRecord::Base.connection.execute('SET CONSTRAINTS ALL IMMEDIATE;')

      unless result
        raise Error, "Failed to load test data: #{dump_path}"
      end
    end

    private

    def connection_options
      config = if ActiveRecord::Base.respond_to?(:connection_db_config)
        ActiveRecord::Base.connection_db_config.configuration_hash
      else
        ActiveRecord::Base.connection_config
      end

      options = []
      options << "-h #{config[:host]}" if config[:host]
      options << "-p #{config[:port]}" if config[:port]
      options << "-U #{config[:username]}" if config[:username]
      options << "-d #{config[:database]}"
      options.join(" ")
    end
  end
end