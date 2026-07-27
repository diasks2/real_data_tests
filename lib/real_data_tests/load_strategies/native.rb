# frozen_string_literal: true

module RealDataTests
  module LoadStrategies
    # Loads a SQL dump on the ActiveRecord connection, so the data
    # participates in the caller's transaction (e.g. DatabaseCleaner's
    # :transaction strategy) and rolls back with it.
    #
    # Dumps without COPY ... FROM stdin blocks are sent as a single
    # multi-statement execute (one server round-trip). Dumps containing COPY
    # blocks fall back to block-by-block execution, streaming COPY data
    # through raw_connection.copy_data on the same libpq session.
    class Native < Base
      def call(dump_path)
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
        ActiveRecord::Base.connection.execute(block.content)
      end
    end
  end
end
