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

    def load_real_test_data_native(name)
      dump_path = File.join(RealDataTests.configuration.dump_path, "#{name}.sql")
      raise Error, "Test data file not found: #{dump_path}" unless File.exist?(dump_path)

      sql_content = File.read(dump_path)

      ActiveRecord::Base.transaction do
        connection = ActiveRecord::Base.connection

        # Disable foreign key checks
        connection.execute('SET session_replication_role = replica;')

        begin
          if sql_content.match?(/^COPY .* FROM stdin/i)
            blocks = parse_sql_blocks(sql_content)
            blocks.each_with_index do |block, index|
              execute_block(block, index + 1, blocks.length)
            end
          else
            # No COPY blocks: send the whole dump in one round-trip. The
            # server parses the multi-statement string, so semicolons inside
            # string literals are handled correctly without client-side splitting.
            connection.execute(sql_content)
          end
        ensure
          connection.execute('SET session_replication_role = DEFAULT;')
        end
      end
    end

    # Loads on the ActiveRecord connection so the data participates in the
    # caller's transaction (e.g. DatabaseCleaner :transaction strategy).
    alias_method :load_real_test_data, :load_real_test_data_native

    private

    def parse_sql_blocks(content)
      blocks = []
      current_block = []
      in_copy_block = false

      content.each_line do |line|
        line = line.chomp

        # Skip empty lines and comments unless in COPY block
        next if !in_copy_block && (line.empty? || line.start_with?('--'))

        # Handle start of COPY block
        if !in_copy_block && line.upcase.match?(/\ACOPY.*FROM stdin/i)
          current_block = [line]
          in_copy_block = true
          next
        end

        # Handle end of COPY block
        if in_copy_block && line == '\\.'
          current_block << line
          blocks << SqlBlock.new(current_block.join("\n"))
          current_block = []
          in_copy_block = false
          next
        end

        # Accumulate lines in COPY block
        if in_copy_block
          current_block << line
          next
        end

        # Handle regular SQL statements
        current_block << line
        if line.end_with?(';')
          blocks << SqlBlock.new(current_block.join("\n"))
          current_block = []
        end
      end

      # Handle any remaining block
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
      # puts "Executing INSERT block #{index}/#{total} for table: #{block.table_name}"
      # Don't modify statements that already end with semicolon
      statement = if block.content.strip.end_with?(';')
        block.content
      else
        "#{block.content};"
      end

      begin
        ActiveRecord::Base.connection.execute(statement)
      rescue ActiveRecord::StatementInvalid => e
        if e.message.include?('syntax error at or near "ON"')
          # Try alternative formatting for ON CONFLICT
          modified_statement = statement.gsub(/\)\s+ON\s+CONFLICT/, ') ON CONFLICT')
          ActiveRecord::Base.connection.execute(modified_statement)
        else
          raise
        end
      end
    end

    def execute_copy_block(block, index, total)
      # puts "Executing COPY block #{index}/#{total}"
      lines = block.content.lines.map(&:chomp)
      copy_statement = lines.shift
      data_lines = lines.take_while { |line| line != '\\.' }

      # raw_connection is the same libpq session as the AR connection, so the
      # COPY participates in the surrounding transaction.
      raw = ActiveRecord::Base.connection.raw_connection
      raw.copy_data(copy_statement) do
        data_lines.each { |line| raw.put_copy_data("#{line}\n") }
      end
    end

    def execute_regular_block(block, index, total)
      # puts "Executing block #{index}/#{total} of type: #{block.type}"
      ActiveRecord::Base.connection.execute(block.content)
    end

    def normalize_insert_statement(statement)
      # First clean up any excess whitespace around parentheses
      statement = statement.gsub(/\(\s+/, '(')
                          .gsub(/\s+\)/, ')')
                          .gsub(/\)\s+ON\s+CONFLICT/, ') ON CONFLICT')

      # Ensure proper spacing around ON CONFLICT
      if statement =~ /(.*?)\s*ON\s+CONFLICT\s+(.*?)\s*(?:DO\s+.*?)?\s*;\s*\z/i
        base = $1.strip
        conflict_part = $2.strip
        action_part = $3&.strip || 'DO NOTHING'

        # Rebuild the statement with consistent formatting
        "#{base} ON CONFLICT #{conflict_part} #{action_part};"
      else
        # If no ON CONFLICT clause, just clean up the spacing
        statement.strip.sub(/;?\s*$/, ';')
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