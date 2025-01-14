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
              # Clean up any formatting issues that might cause syntax errors
              cleaned_statement = clean_sql_statement(statement)
              connection.execute(cleaned_statement)
            rescue ActiveRecord::StatementInvalid => e
              # Provide detailed error information
              raise Error, "Failed to execute SQL statement: #{e.message}\nStatement: #{cleaned_statement}"
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

          def clean_sql_statement(statement)
        # Handle VALUES clause formatting
        if statement.include?('VALUES')
          # Split into pre-VALUES and VALUES parts
          parts = statement.split(/VALUES\s*\(/i, 2)
          if parts.length == 2
            # Get the column names from the first part
            column_names = parts[0].scan(/\((.*?)\)/).flatten.first&.split(',')&.map(&:strip) || []

            # Split values into individual items
            values_part = parts[1]
            values = split_values(values_part)

            # Process each value according to its column and position
            values.each_with_index do |value, i|
              # Skip if already properly quoted
              next if value.start_with?("'") && value.end_with?("'")

              # Quote UUIDs
              if value.match?(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
                values[i] = "'#{value}'"
              # Quote any non-NULL string values that contain spaces or special characters
              elsif !['NULL', 'true', 'false'].include?(value) &&
                    !value.match?(/^\d+$/) && # not a number
                    !value.start_with?("'{") && # not a JSON object
                    !value.start_with?("'") # not already quoted
                values[i] = "'#{value}'"
              end
            end

            # Reassemble the statement with any trailing ON CONFLICT clause
            remainder = values_part.match(/\)\s*(ON\s+CONFLICT.*?)(;?\s*$)/i)
            statement = parts[0] + 'VALUES (' + values.join(', ') + ')'
            statement += " #{remainder[1]};" if remainder
          end
        end

        statement
      end

      def split_values(values_part)
        values = []
        current_value = ''
        in_quotes = false
        in_json = false
        depth = 0

        values_part.chars.each_with_index do |char, i|
          case char
          when "'"
            # Toggle quote state if not escaped
            if i == 0 || values_part[i-1] != '\\'
              in_quotes = !in_quotes
            end
          when '{'
            depth += 1 unless in_quotes
            in_json = true unless in_quotes
          when '}'
            depth -= 1 unless in_quotes
          when ','
            if !in_quotes && depth == 0
              values << current_value.strip
              current_value = ''
              next
            end
          end
          current_value << char
        end

        # Add the last value (remove trailing ';' or ')')
        last_value = current_value.strip
        last_value = last_value[0..-2] if last_value.end_with?(';', ')')
        values << last_value

        values
      end
  end
end