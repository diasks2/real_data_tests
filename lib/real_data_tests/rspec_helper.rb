module RealDataTests
  module RSpecHelper
    class SqlBlock
      attr_reader :type, :content, :table_name

      def initialize(content)
        @content = content.strip
        @type = determine_block_type
        @table_name = extract_table_name if @type == :insert
      end

      private

      def determine_block_type
        case @content
        when /\AINSERT INTO/i
          :insert
        when /\ACOPY.*FROM stdin/i
          :copy
        when /\AALTER TABLE/i
          :alter
        when /\ASET/i
          :set
        else
          :other
        end
      end

      def extract_table_name
        if @content =~ /INSERT INTO\s+"?([^\s"(]+)"?\s/i
          $1
        end
      end
    end

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

    def load_real_test_data_native(name)
      dump_path = File.join(RealDataTests.configuration.dump_path, "#{name}.sql")
      raise Error, "Test data file not found: #{dump_path}" unless File.exist?(dump_path)

      sql_content = File.read(dump_path)
      blocks = parse_sql_blocks(sql_content)

      ActiveRecord::Base.transaction do
        connection = ActiveRecord::Base.connection

        # Disable foreign key checks
        connection.execute('SET session_replication_role = replica;')

        begin
          blocks.each_with_index do |block, index|
            execute_block(block, index + 1, blocks.length)
          end
        ensure
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

    def parse_sql_blocks(content)
      blocks = []
      current_block = []
      in_copy_block = false

      content.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?('--')

        if line.upcase.start_with?('COPY') && line.upcase.include?('FROM stdin')
          in_copy_block = true
          current_block << line
        elsif line == '\.' && in_copy_block
          in_copy_block = false
          current_block << line
          blocks << SqlBlock.new(current_block.join("\n"))
          current_block = []
        elsif in_copy_block
          current_block << line
        else
          # Handle regular SQL statements
          current_block << line
          if line.end_with?(';') && !in_copy_block
            blocks << SqlBlock.new(current_block.join("\n"))
            current_block = []
          end
        end
      end

      # Add any remaining block
      blocks << SqlBlock.new(current_block.join("\n")) unless current_block.empty?
      blocks
    end

    def execute_block(block, index, total)
      case block.type
      when :insert
        execute_insert_block(block, index, total)
      when :copy
        execute_copy_block(block, index, total)
      else
        execute_regular_block(block, index, total)
      end
    end

    def execute_insert_block(block, index, total)
      puts "Executing INSERT block #{index}/#{total} for table: #{block.table_name}"
      statement = normalize_insert_statement(block.content)
      ActiveRecord::Base.connection.execute(statement)
    end

    def execute_copy_block(block, index, total)
      puts "Executing COPY block #{index}/#{total}"
      ActiveRecord::Base.connection.execute(block.content)
    end

    def execute_regular_block(block, index, total)
      puts "Executing block #{index}/#{total} of type: #{block.type}"
      ActiveRecord::Base.connection.execute(block.content)
    end

    def normalize_insert_statement(statement)
      # Handle ON CONFLICT clauses properly
      if statement =~ /(.*?)\s+(ON\s+CONFLICT.*?)\s*;\s*\z/i
        main_insert = $1
        conflict_clause = $2
        "#{main_insert} #{conflict_clause};"
      else
        statement
      end
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

      # Normalize `ON CONFLICT` clauses
      statements = statements.each_with_object([]) do |stmt, result|
        if stmt.strip.upcase.start_with?('ON CONFLICT')
          result[-1] = "#{result.last.strip} #{stmt.strip}"
        else
          result << stmt.strip
        end
      end

      # Ensure semicolons and spacing
      statements.map! do |stmt|
        stmt = stmt.gsub(/\)\s*ON CONFLICT/, ') ON CONFLICT') # Normalize spacing
        stmt.strip.end_with?(';') ? stmt.strip : "#{stmt.strip};"
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
end