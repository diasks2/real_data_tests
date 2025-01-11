module RealDataTests
  class RecordCollector
    def initialize(record)
      @record = record
      @collected_records = Set.new
      @collection_stats = Hash.new { |h, k| h[k] = { count: 0, associations: Hash.new(0) } }
      @processed_associations = Set.new # Track processed association pairs to prevent cycles
    end

    def collect
      puts "\nStarting record collection from: #{@record.class.name}##{@record.id}"
      filter_mode = RealDataTests.configuration.association_filter_mode
      filter_list = RealDataTests.configuration.association_filter_list
      puts "Using #{filter_mode || 'no'} filter with #{filter_list.any? ? filter_list.join(', ') : 'no associations'}"
      collect_record(@record)
      print_collection_stats
      @collected_records.to_a
    end

    private

    def collect_record(record)
      return if @collected_records.include?(record)
      return unless record # Guard against nil records

      @collected_records.add(record)
      @collection_stats[record.class.name][:count] += 1
      collect_associations(record)
    end

    def collect_associations(record)
      return unless record.class.respond_to?(:reflect_on_all_associations)

      associations = record.class.reflect_on_all_associations
      puts "\nProcessing associations for: #{record.class.name}##{record.id}"
      puts "Found #{associations.length} associations"

      associations.each do |association|
        association_key = "#{record.class.name}##{record.id}:#{association.name}"
        next if @processed_associations.include?(association_key)
        @processed_associations.add(association_key)

        should_process = RealDataTests.configuration.should_process_association?(association.name)
        unless should_process
          puts "  Skipping #{RealDataTests.configuration.association_filter_mode == :whitelist ? 'non-whitelisted' : 'blacklisted'} association: #{association.name}"
          next
        end

        puts "  Processing #{association.macro} association: #{association.name}"

        begin
          related_records = fetch_related_records(record, association)
          count = related_records.length
          puts "    Found #{count} related #{association.name} records"
          @collection_stats[record.class.name][:associations][association.name] += count

          related_records.each { |related_record| collect_record(related_record) }
        rescue => e
          puts "    Error processing association #{association.name}: #{e.message}"
        end
      end
    end

    def fetch_related_records(record, association)
      case association.macro
      when :belongs_to, :has_one
        Array(record.public_send(association.name)).compact
      when :has_many, :has_and_belongs_to_many
        # Force load the association to ensure we get all records
        relation = record.public_send(association.name)
        relation.loaded? ? relation.to_a : relation.load.to_a
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
      end
      puts "\nTotal unique records collected: #{@collected_records.size}"
      puts "==============================\n"
    end
  end
end