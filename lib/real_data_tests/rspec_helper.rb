module RealDataTests
  module RSpecHelper
    def load_real_test_data(name)
      dump_path = File.join(RealDataTests.configuration.dump_path, "#{name}.sql")
      raise Error, "Test data file not found: #{dump_path}" unless File.exist?(dump_path)
      ActiveRecord::Base.transaction do
        # Disable foreign key checks
        ActiveRecord::Base.connection.execute('SET session_replication_role = replica;')
        begin
          # Load the SQL dump quietly
          result = system("psql #{connection_options} -q < #{dump_path}")
          raise Error, "Failed to load test data: #{dump_path}" unless result
        ensure
          # Re-enable foreign key checks
          ActiveRecord::Base.connection.execute('SET session_replication_role = DEFAULT;')
        end
      end
    end

    # New method that doesn't rely on system commands
    def load_real_test_data_native(name)
      dump_path = File.join(RealDataTests.configuration.dump_path, "#{name}.sql")
      raise Error, "Test data file not found: #{dump_path}" unless File.exist?(dump_path)

      ActiveRecord::Base.transaction do
        connection = ActiveRecord::Base.connection

        # Disable foreign key checks
        connection.execute('SET session_replication_role = replica;')

        begin
          # Read the SQL file content
          sql_content = File.read(dump_path)

          # Split the file into individual statements
          statements = split_sql_statements(sql_content)

          # Execute each statement
          statements.each do |statement|
            next if statement.strip.empty?
            begin
              connection.execute(statement)
            rescue ActiveRecord::StatementInvalid => e
              raise Error, "Failed to execute SQL statement: #{e.message}"
            end
          end
        ensure
          # Re-enable foreign key checks
          connection.execute('SET session_replication_role = DEFAULT;')
        end
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
      options << "-q"
      options.join(" ")
    end

    def split_sql_statements(sql)
      statements = []
      current_statement = ''
      in_string = false
      escaped = false

      sql.each_char do |char|
        case char
        when '\\'
          escaped = !escaped
        when "'"
          in_string = !in_string unless escaped
          escaped = false
        when ';'
          if !in_string
            statements << current_statement.strip
            current_statement = ''
          else
            current_statement << char
          end
        else
          escaped = false
          current_statement << char
        end
      end

      # Add the last statement if it doesn't end with a semicolon
      statements << current_statement.strip if current_statement.strip.length > 0

      statements
    end
  end
end