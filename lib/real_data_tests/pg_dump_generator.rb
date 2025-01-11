require 'csv'
require 'tmpdir'
require 'fileutils'

module RealDataTests
  class PgDumpGenerator
    def initialize(records)
      @records = records
    end

    def generate
      tables_with_records = @records.group_by { |record| record.class.table_name }

      # Generate only INSERT statements
      insert_statements = collect_inserts(tables_with_records)

      # Write all INSERT statements, no schema or grants
      insert_statements.join("\n")
    end

    private

    def collect_inserts(tables_with_records)
      tables_with_records.map do |table_name, records|
        ids = records.map { |r| quote_value(r.id) }.join(',')
        temp_file = "#{Dir.tmpdir}/#{table_name}_#{Time.now.to_i}.sql"

        # Get the column names for this table
        columns = records.first.class.column_names

        # Use COPY to extract the data
        copy_command = "\\COPY (SELECT * FROM #{table_name} WHERE id IN (#{ids})) TO '#{temp_file}' WITH CSV"
        system("psql #{connection_options} -c \"#{copy_command}\"")

        # Read the data and create INSERT statements
        data = File.read(temp_file)
        statements = data.split("\n").map do |line|
          values = CSV.parse_line(line).map { |val| quote_value(val) }.join(',')
          "INSERT INTO #{table_name} (#{columns.join(', ')}) " \
          "VALUES (#{values}) " \
          "ON CONFLICT (id) DO NOTHING;"
        end

        # Clean up temp file
        FileUtils.rm(temp_file)

        statements
      end.flatten
    end

    def quote_value(value)
      return 'NULL' if value.nil?
      return value if value =~ /^\d+$/  # If it's a number
      "'#{value.to_s.gsub("'", "''")}'" # Escape single quotes for PostgreSQL
    end

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