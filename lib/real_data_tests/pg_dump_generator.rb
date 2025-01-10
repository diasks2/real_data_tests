module RealDataTests
  class PgDumpGenerator
    def initialize(records)
      @records = records
    end

    def generate
      tables_with_records = @records.group_by { |record| record.class.table_name }

      tables_with_records.map do |table_name, records|
        ids = records.map(&:id).join(',')

        "pg_dump #{connection_options} --table=#{table_name} " \
        "--data-only --column-inserts " \
        "--where='id IN (#{ids})'"
      end.join(" && ")
    end

    private

    def connection_options
      config = ActiveRecord::Base.connection_config
      options = []
      options << "-h #{config[:host]}" if config[:host]
      options << "-p #{config[:port]}" if config[:port]
      options << "-U #{config[:username]}" if config[:username]
      options << "-d #{config[:database]}"
      options.join(" ")
    end
  end
end