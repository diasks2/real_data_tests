# frozen_string_literal: true

module RealDataTests
  module LoadStrategies
    # Loads a SQL dump by shelling out to psql. The psql subprocess uses its
    # own Postgres connection, so the loaded data commits immediately and does
    # NOT participate in the caller's transaction (a transaction is
    # per-connection; a child process can never join it).
    #
    # This is the default strategy of load_real_test_data. Prefer the Native
    # strategy (load_real_test_data_native) unless the dump requires psql
    # itself — e.g. psql meta-commands (\set, \connect) or dumps too large to
    # read into memory.
    class Psql < Base
      def call(dump_path)
        # Load the SQL dump quietly. Invoked without a shell (argv array +
        # :in redirect), so paths and connection values need no escaping.
        # Note: no transaction or session_replication_role handling here —
        # psql runs on its own Postgres session, so nothing set on the
        # ActiveRecord connection can affect the load.
        result = system('psql', *connection_args, in: dump_path)
        raise Error, "Failed to load test data: #{dump_path}" unless result
      end

      private

      def connection_args
        config = if ActiveRecord::Base.respond_to?(:connection_db_config)
          ActiveRecord::Base.connection_db_config.configuration_hash
        else
          ActiveRecord::Base.connection_config
        end
        args = []
        args += ['-h', config[:host].to_s] if config[:host]
        args += ['-p', config[:port].to_s] if config[:port]
        args += ['-U', config[:username].to_s] if config[:username]
        args += ['-d', config[:database].to_s]
        args << '-q'
        args
      end
    end
  end
end
