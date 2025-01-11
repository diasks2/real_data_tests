module RealDataTests
  class PgDumpGenerator
    def initialize(records)
      @records = records
    end

    def generate
      tables_with_records = @records.group_by { |record| record.class.table_name }

      tables_with_records.map do |table_name, records|
        ids = records.map { |r| quote_value(r.id) }.join(',')

        "pg_dump #{connection_options} --table=#{table_name} " \
        "--data-only --column-inserts " \
        "--where \"id IN (#{ids})\""
      end.join(" && ")
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