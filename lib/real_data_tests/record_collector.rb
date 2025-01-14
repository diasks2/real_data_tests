module RealDataTests
  class RecordCollector
    attr_reader :collection_stats, :collected_records

    def initialize(record)
      @record = record
      @collected_records = Set.new
      @collection_stats = {}
      @processed_associations = Set.new
      @association_path = []
      @current_depth = 0
      @visited_associations = {}

      # Initialize stats for the record's class
      @collection_stats[record.class.name] = {
        count: 0,
        associations: Hash.new(0),
        polymorphic_types: {}
      }

      record.class.reflect_on_all_associations(:belongs_to).each do |assoc|
        if assoc.polymorphic?
          @collection_stats[record.class.name][:polymorphic_types][assoc.name.to_s] ||= Set.new
        end
      end

      puts "\nInitializing RecordCollector for #{record.class.name}##{record.id}"
      record.class.reflect_on_all_associations(:belongs_to).each do |assoc|
        if assoc.polymorphic?
          type = record.public_send("#{assoc.name}_type")
          id = record.public_send("#{assoc.name}_id")
          puts "Found polymorphic belongs_to '#{assoc.name}' with type: #{type}, id: #{id}"
        end
      end
    end

    def collect
      puts "\nStarting record collection from: #{@record.class.name}##{@record.id}"
      filter_mode = RealDataTests.configuration.current_preset.association_filter_mode
      filter_list = RealDataTests.configuration.current_preset.association_filter_list
      puts "Using #{filter_mode || 'no'} filter with #{filter_list.any? ? filter_list.join(', ') : 'no associations'}"
      collect_record(@record, 0)
      print_collection_stats
      @collected_records.to_a
    end

    private

    def collect_record(record, depth)
      return if @collected_records.include?(record)
      return unless record # Guard against nil records
      return if depth > RealDataTests.configuration.current_preset.max_depth

      puts "\nCollecting record: #{record.class.name}##{record.id}"
      @collected_records.add(record)

      # Initialize stats structure
      @collection_stats[record.class.name] ||= {
        count: 0,
        associations: {},
        polymorphic_types: {}
      }
      @collection_stats[record.class.name][:count] += 1

      # Track types for polymorphic belongs_to associations
      record.class.reflect_on_all_associations(:belongs_to).each do |assoc|
        next unless assoc.polymorphic?

        type = record.public_send("#{assoc.name}_type")
        @collection_stats[record.class.name][:polymorphic_types][assoc.name.to_sym] ||= Set.new

        begin
          associated_record = record.public_send(assoc.name)
          if associated_record
            puts "  Adding polymorphic type '#{type}' for #{assoc.name}"
            @collection_stats[record.class.name][:polymorphic_types][assoc.name.to_sym] << associated_record.class.name
          else
            puts "  Skipping polymorphic type for #{assoc.name} due to missing associated record"
          end
        rescue StandardError => e
          puts "  Error loading polymorphic association #{assoc.name}: #{e.message}"
        end
      end

      collect_associations(record, depth)
    end

    def collect_associations(record, depth)
      return unless record.class.respond_to?(:reflect_on_all_associations)
      return if depth >= RealDataTests.configuration.current_preset.max_depth

      associations = record.class.reflect_on_all_associations
      puts "\nProcessing associations for: #{record.class.name}##{record.id}"
      puts "Found #{associations.length} associations"

      associations.each do |association|
        association_key = "#{record.class.name}##{record.id}:#{association.name}"
        puts "  Checking if should process: #{association_key}"

        if RealDataTests.configuration.current_preset.prevent_reciprocal?(record.class, association.name)
          track_key = "#{record.class.name}:#{association.name}"
          @visited_associations[track_key] ||= Set.new

          # Skip if we've already processed this association type for this class
          if @visited_associations[track_key].any?
            puts "    Skipping prevented reciprocal association: #{track_key}"
            next
          end
          @visited_associations[track_key].add(record.id)
        end

        next unless should_process_association?(record, association, depth)

        puts "  Processing #{association.macro} #{association.polymorphic? ? 'polymorphic ' : ''}association: #{association.name}"
        process_association(record, association, depth)
      end
    end

    def should_process_association?(record, association, depth = 0)
      return false if depth >= RealDataTests.configuration.current_preset.max_depth

      association_key = "#{record.class.name}##{record.id}:#{association.name}"
      return false if @processed_associations.include?(association_key)

      # Check if the association is allowed by configuration
      should_process = RealDataTests.configuration.current_preset.should_process_association?(record, association.name)
      puts "  Configuration says: #{should_process}"

      if should_process
        @processed_associations.add(association_key)
        true
      else
        false
      end
    end

    def process_association(record, association, depth)
      @association_path.push(association.name)

      begin
        if detect_circular_dependency?(record, association)
          puts "    Skipping circular dependency for #{association.name} on #{record.class.name}##{record.id}"
          return
        end

        related_records = fetch_related_records(record, association)
        count = related_records.length
        puts "    Found #{count} related #{association.name} records"

        @collection_stats[record.class.name][:associations][association.name.to_s] ||= 0
        @collection_stats[record.class.name][:associations][association.name.to_s] += count

        related_records.each { |related_record| collect_record(related_record, depth + 1) }
      rescue => e
        puts "    Error processing association #{association.name}: #{e.message}"
      ensure
        @association_path.pop
      end
    end

    def self_referential_association?(klass, association)
      return false unless association.options[:class_name]
      return false if association.polymorphic?
      association.options[:class_name] == klass.name
    end

    def detect_circular_dependency?(record, association)
      return false unless association.belongs_to?
      return false if association.polymorphic?

      target_class = association.klass
      return false unless target_class

      path_key = "#{target_class.name}:#{association.name}"
      visited_count = @association_path.count { |assoc| "#{target_class.name}:#{assoc}" == path_key }

      visited_count > 1
    end

    def fetch_related_records(record, association)
      case association.macro
      when :belongs_to, :has_one
        Array(record.public_send(association.name)).compact
      when :has_many, :has_and_belongs_to_many
        relation = record.public_send(association.name)

        if limit = RealDataTests.configuration.current_preset.get_association_limit(record.class, association.name)
          puts "    Applying configured limit of #{limit} records for #{record.class.name}.#{association.name}"
          relation = relation[0...limit]
        end

        relation
      else
        []
      end
    end

    def print_collection_stats
      puts "\n=== Collection Statistics ==="
      @collection_stats.each do |model, stats|
        puts "\n#{model}:"
        puts "  Total records: #{stats[:count]}"

        if stats[:associations].any?
          puts "  Associations:"
          stats[:associations].each do |assoc_name, count|
            puts "    #{assoc_name}: #{count} records"
          end
        end

        if stats[:polymorphic_types].any?
          puts "  Polymorphic Types:"
          stats[:polymorphic_types].each do |assoc_name, types|
            puts "    #{assoc_name}: #{types.to_a.join(', ')}"
          end
        end
      end
      puts "\nTotal unique records collected: #{@collected_records.size}"
      puts "==============================\n"
    end
  end
end