module RealDataTests
  class PgDumpGenerator
    def initialize(records)
      @records = records
    end

    def generate
      tables_with_records = @records.group_by { |record| record.class.table_name }

      commands = tables_with_records.map do |table_name, records|
        ids = records.map { |r| quote_value(r.id) }.join(',')

        # Create a temporary view for the selected records
        tmp_view_name = "tmp_#{table_name}_#{Time.now.to_i}"
        view_creation = "psql #{connection_options} -c \"CREATE VIEW #{tmp_view_name} AS SELECT * FROM #{table_name} WHERE id IN (#{ids})\""

        # Dump the view
        dump_command = "pg_dump #{connection_options} --table=#{tmp_view_name} --data-only --column-inserts"

        # Clean up the view
        cleanup_command = "psql #{connection_options} -c \"DROP VIEW #{tmp_view_name}\""

        # Combine commands and fix the table name in the output
        "(#{view_creation} && #{dump_command} | sed 's/#{tmp_view_name}/#{table_name}/g' && #{cleanup_command})"
      end

      commands.join(" && ")
    end

    private

    def quote_value(value)
      if value.is_a?(String) # Handle UUIDs
        "'#{value}'"
      else
        value
      end
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