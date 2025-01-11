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

      # Create a temporary file for each table's copy command
      temp_files = tables_with_records.map do |table_name, records|
        ids = records.map { |r| quote_value(r.id) }.join(',')
        temp_file = "#{Dir.tmpdir}/#{table_name}_#{Time.now.to_i}.sql"

        # Use psql to export just the records we want
        system("psql #{connection_options} -c \"\\COPY (SELECT * FROM #{table_name} WHERE id IN (#{ids})) TO '#{temp_file}' WITH CSV\"")

        # Now use pg_dump to create proper INSERT statements
        command = "pg_dump #{connection_options} --table=#{table_name} --schema-only --no-owner | grep -v '^--' | grep -v '^SET' | grep -v '^SELECT' > #{temp_file}.schema"
        system(command)

        { table: table_name, data: temp_file, schema: "#{temp_file}.schema" }
      end

      # Combine all the files
      result = temp_files.map do |file|
        # Get the schema (INSERT statement structure)
        schema = File.read(file[:schema])
        data = File.read(file[:data])

        # Convert CSV to INSERT statements
        insert_statements = data.split("\n").map do |line|
          values = CSV.parse_line(line).map { |val| quote_value(val) }.join(',')
          "INSERT INTO #{file[:table]} VALUES (#{values});"
        end.join("\n")

        # Clean up temp files
        FileUtils.rm(file[:data])
        FileUtils.rm(file[:schema])

        schema + "\n" + insert_statements
      end.join("\n\n")

      result
    end

    private

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