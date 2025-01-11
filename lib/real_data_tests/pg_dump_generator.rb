require 'csv'
require 'tmpdir'
require 'fileutils'

module RealDataTests
  class PgDumpGenerator
    def initialize(records)
      @records = records
    end

    def generate
      tables_with_records = order_by_dependencies(
        @records.group_by { |record| record.class.table_name }
      )

      tables_with_records.map do |table_name, records|
        ids = records.map { |r| quote_value(r.id) }.join(',')
        temp_file = "#{Dir.tmpdir}/#{table_name}_#{Time.now.to_i}.sql"

        # Use psql to export just the INSERT statements for the records we want
        system("psql #{connection_options} -c \"\\COPY (SELECT * FROM #{table_name} WHERE id IN (#{ids})) TO '#{temp_file}' WITH CSV\"")

        data = File.read(temp_file)

        # Convert CSV to INSERT statements
        insert_statements = data.split("\n").map do |line|
          values = CSV.parse_line(line).map { |val| quote_value(val) }.join(',')
          "INSERT INTO #{table_name} VALUES (#{values}) ON CONFLICT (id) DO NOTHING;"
        end.join("\n")

        # Clean up temp file
        FileUtils.rm(temp_file)

        insert_statements
      end.join("\n\n")
    end

    private

    def order_by_dependencies(tables_with_records)
      # Get all models
      models = tables_with_records.keys.map { |table_name|
        table_name.classify.constantize
      }

      # Sort based on foreign key dependencies
      sorted_models = models.sort_by do |model|
        model.reflect_on_all_associations(:belongs_to).count
      end

      # Reconstruct the hash in sorted order
      sorted_models.map { |model|
        [model.table_name, tables_with_records[model.table_name]]
      }.to_h
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