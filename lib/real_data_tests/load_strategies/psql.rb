# frozen_string_literal: true

module RealDataTests
  module LoadStrategies
    # Loads a SQL dump by shelling out to psql. The psql subprocess uses its
    # own Postgres connection, so the loaded data commits immediately and does
    # NOT participate in the caller's transaction (a transaction is
    # per-connection; a child process can never join it).
    #
    # Use this only when the dump requires psql itself — e.g. psql
    # meta-commands (\set, \connect) or dumps too large to read into memory.
    # For everything else, prefer the (default) Native strategy.
    class Psql < Base
      def call(dump_path)
        # Load the SQL dump quietly. Note: no transaction or
        # session_replication_role handling here — psql runs on its own
        # Postgres session, so nothing set on the ActiveRecord connection
        # (as pre-0.5 versions did) can affect the load.
        result = system("psql #{connection_options} -q < #{dump_path}")
        raise Error, "Failed to load test data: #{dump_path}" unless result
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
    end
  end
end
