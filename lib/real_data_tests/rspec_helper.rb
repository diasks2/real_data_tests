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

    # Native Ruby implementation
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
        if char == '\\'
          escaped = !escaped
        elsif char == "'" && !escaped
          in_string = !in_string
        elsif char == ';' && !in_string
          # Add the completed statement
          statements << current_statement.strip unless current_statement.strip.empty?
          current_statement = ''
          next
        end
        escaped = false
        current_statement << char
      end

      # Add the last statement if it exists
      statements << current_statement.strip unless current_statement.strip.empty?

      # Ensure `ON CONFLICT` stays with the previous statement
      statements = statements.each_with_object([]) do |stmt, result|
        if stmt.strip.upcase.start_with?('ON CONFLICT')
          result[-1] = "#{result.last.strip} #{stmt.strip}"
        else
          result << stmt.strip
        end
      end

      # Normalize spacing around `ON CONFLICT` and ensure semicolons
      statements.map! do |stmt|
        stmt = stmt.gsub(/\)\s*ON CONFLICT/, ') ON CONFLICT') # Normalize spacing
        stmt.strip.end_with?(';') ? stmt.strip : "#{stmt.strip};" # Ensure semicolon
      end

      statements
    end

    def extract_conflict_clause(statement)
      # Use a more precise regex that handles multiple closing parentheses
      if statement =~ /(.+?\))\s*(ON\s+CONFLICT\s+.*?)(?:;?\s*$)/i
        [$1, $2.strip]
      else
        [statement.sub(/;?\s*$/, ''), nil]
      end
    end

    def clean_sql_statement(statement)
      # Match either INSERT INTO...VALUES or just VALUES
      if statement =~ /(?:INSERT INTO.*)?VALUES\s*\(/i
        # Split the statement into parts, being careful with the ending
        if statement =~ /(.*?VALUES\s*\()(.*)(\)\s*(?:ON CONFLICT.*)?;?\s*$)/i
          pre_values = $1
          values_content = $2
          post_values = $3

          # Clean the values content while preserving complex JSON
          cleaned_values = clean_complex_values(values_content)

          # Reassemble the statement, ensuring exactly one semicolon at the end
          statement = "#{pre_values}#{cleaned_values}#{post_values}"
          statement = statement.gsub(/;*\s*$/, '')  # Remove any trailing semicolons and whitespace
          statement += ";"
        end
      end
      statement
    end

    def clean_complex_values(values_str)
      current_value = ''
      values = []
      in_quotes = false
      in_json = false
      json_brace_count = 0
      escaped = false

      chars = values_str.chars
      i = 0
      while i < chars.length
        char = chars[i]

        case char
        when '\\'
          current_value << char
          escaped = !escaped
        when "'"
          if !escaped
            in_quotes = !in_quotes
          end
          escaped = false
          current_value << char
        when '{'
          if !in_quotes
            in_json = true
            json_brace_count += 1
          end
          current_value << char
        when '}'
          if !in_quotes
            json_brace_count -= 1
            in_json = json_brace_count > 0
          end
          current_value << char
        when ','
          if !in_quotes && !in_json
            values << clean_value(current_value.strip)
            current_value = ''
          else
            current_value << char
          end
        else
          escaped = false
          current_value << char
        end
        i += 1
      end

      # Add the last value
      values << clean_value(current_value.strip) unless current_value.strip.empty?

      values.join(', ')
    end

    def clean_value(value)
      return value if value.start_with?("'") # Already quoted
      return value if value.start_with?("'{") # JSON object
      return 'NULL' if value.upcase == 'NULL'
      return value.downcase if ['true', 'false'].include?(value.downcase)
      return value if value.match?(/^\d+$/) # Numbers

      if value.match?(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
        "'#{value}'" # UUID
      else
        # Handle any other string value, including those with commas
        "'#{value}'" # Other strings
      end
    end
  end

  def import
    @logger.info "Starting SQL import..."

    ActiveRecord::Base.transaction do
      begin
        # Disable foreign key checks and triggers temporarily
        ActiveRecord::Base.connection.execute('SET session_replication_role = replica;')

        # Split the SQL content into individual statements
        statements = split_sql_statements(@sql_content)

        statements.each_with_index do |statement, index|
          next if statement.strip.empty?

          begin
            @logger.info "Executing statement #{index + 1} of #{statements.length}"
            cleaned_statement = clean_sql_statement(statement)
            ActiveRecord::Base.connection.execute(cleaned_statement)
          rescue ActiveRecord::StatementInvalid => e
            @logger.error "Error executing statement #{index + 1}: #{e.message}"
            @logger.error "Statement: #{cleaned_statement[0..100]}..."
            raise
          end
        end

        @logger.info "Successfully imported all SQL statements"
      rescue StandardError => e
        @logger.error "Error during import: #{e.message}"
        @logger.error e.backtrace.join("\n")
        raise
      ensure
        # Re-enable foreign key checks and triggers
        ActiveRecord::Base.connection.execute('SET session_replication_role = DEFAULT;')
      end
    end
  end
end