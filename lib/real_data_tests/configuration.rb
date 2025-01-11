module RealDataTests
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end

  class Configuration
    attr_accessor :dump_path, :cleanup_models
    attr_reader :association_filter_mode, :association_filter_list, :anonymization_rules

    def initialize
      @dump_path = 'spec/fixtures/real_data_dumps'
      @anonymization_rules = {}
      @association_filter_mode = nil
      @association_filter_list = []
      @cleanup_models = []
      @delayed_anonymizations = []
    end

    def anonymize(model_name, mappings = {})
      if !defined?(Rails) || !Rails.application.initialized?
        @delayed_anonymizations << [model_name, mappings]
        return
      end

      begin
        model = model_name.to_s.constantize
        @anonymization_rules[model_name.to_s] = mappings
      rescue => e
        warn "Note: Anonymization for #{model_name} will be configured when Rails is fully initialized."
      end
    end

    def process_delayed_anonymizations
      return unless @delayed_anonymizations

      @delayed_anonymizations.each do |model_name, mappings|
        anonymize(model_name, mappings)
      end
      @delayed_anonymizations = []
    end

    def exclude_associations(*associations)
      if @association_filter_mode == :whitelist
        raise Error, "Cannot set excluded_associations when included_associations is already set"
      end

      @association_filter_mode = :blacklist
      @association_filter_list = associations.flatten
    end

    def include_associations(*associations)
      if @association_filter_mode == :blacklist
        raise Error, "Cannot set included_associations when excluded_associations is already set"
      end

      @association_filter_mode = :whitelist
      @association_filter_list = associations.flatten
    end

    def configure_cleanup(*models)
      @cleanup_models = models.flatten
    end

    def should_process_association?(association_name)
      case @association_filter_mode
      when :whitelist
        @association_filter_list.include?(association_name)
      when :blacklist
        !@association_filter_list.include?(association_name)
      else
        true
      end
    end
  end

  class Error < StandardError; end

  class Railtie < Rails::Railtie
    config.before_configuration do
      # Ensure configuration is initialized before Rails configuration
      RealDataTests.configuration
    end

    config.after_initialize do
      if RealDataTests.configuration
        RealDataTests.configuration.process_delayed_anonymizations
      end
    end
  end
end

# Initialize configuration on require
RealDataTests.configuration