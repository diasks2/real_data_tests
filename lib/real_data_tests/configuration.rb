module RealDataTests
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

    # Only setup anonymization if we're in the right environment
    def anonymize(model_name, mappings = {})
      # Store the anonymization for later if Rails isn't fully loaded
      if !defined?(Rails) || !Rails.application.initialized?
        @delayed_anonymizations << [model_name, mappings]
        return
      end

      model = model_name.to_s.constantize
      @anonymization_rules[model_name.to_s] = mappings
    rescue => e
      # Log warning but don't fail
      warn "Note: Anonymization for #{model_name} will be configured when Rails is fully initialized."
    end

    def process_delayed_anonymizations
      return unless @delayed_anonymizations

      @delayed_anonymizations.each do |model_name, mappings|
        anonymize(model_name, mappings)
      end
      @delayed_anonymizations = []
    end

    # Set associations to exclude (blacklist mode)
    def exclude_associations(*associations)
      raise Error, "Cannot set excluded_associations when included_associations is already set" if @association_filter_mode == :whitelist
      @association_filter_mode = :blacklist
      @association_filter_list = associations.flatten
    end

    # Add a method for configuring cleanup
    def configure_cleanup(*models)
      @cleanup_models = models.flatten
    end

    # Set associations to include (whitelist mode)
    def include_associations(*associations)
      raise Error, "Cannot set included_associations when excluded_associations is already set" if @association_filter_mode == :blacklist
      @association_filter_mode = :whitelist
      @association_filter_list = associations.flatten
    end

    def should_process_association?(association_name)
      case @association_filter_mode
      when :whitelist
        @association_filter_list.include?(association_name)
      when :blacklist
        !@association_filter_list.include?(association_name)
      else
        true # If no filter mode is set, process all associations
      end
    end
  end
end