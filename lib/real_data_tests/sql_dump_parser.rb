# frozen_string_literal: true

module RealDataTests
  # Splits a SQL dump into executable blocks. Regular statements become one
  # block each (terminated by ";"); COPY ... FROM stdin blocks span from the
  # COPY line through the "\." terminator, preserving the data lines between.
  class SqlDumpParser
    # A single parsed block of the dump, tagged with its statement type.
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

    # Returns an array of SqlBlock in dump order.
    def parse(content)
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
  end
end
