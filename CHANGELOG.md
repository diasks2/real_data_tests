## [Unreleased]
### Added
- **Load strategies**: SQL dump loading is now pluggable via `RealDataTests::LoadStrategies`
  - `LoadStrategies::Native` (default) — loads on the ActiveRecord connection
  - `LoadStrategies::Psql` — the previous `psql` shell-out behavior, for dumps that require psql itself (meta-commands like `\set`, or dumps too large to read into memory)
  - Inject via `load_real_test_data("dump", strategy: RealDataTests::LoadStrategies::Psql)`
  - Custom strategies: subclass `LoadStrategies::Base` and implement `#call(dump_path)`

### Changed
- `load_real_test_data` behavior is unchanged (psql shell-out, `LoadStrategies::Psql` default); pass `strategy: LoadStrategies::Native` to load transactionally on the ActiveRecord connection so data participates in the caller's transaction (e.g. DatabaseCleaner `:transaction` strategy) and rolls back with it
- Native loader: dumps without `COPY ... FROM stdin` blocks are executed as a single multi-statement `execute` (one server round-trip) instead of parsed and executed block-by-block; block parsing is kept only as the COPY fallback
- Native loader: `COPY ... FROM stdin` blocks are streamed through `raw_connection.copy_data` on the same libpq session, so COPY data is transactional too (previously broken — the whole COPY block went through `execute`)

## [0.4.1] - 2026-04-09
### Fixed
- Fixed `datetime` microsecond precision loss in `PgDumpGenerator`
  - `datetime` columns previously fell through to the default string conversion (`Time#to_s`), dropping sub-second precision
  - Added explicit `:datetime` handling that emits values via `strftime("%Y-%m-%d %H:%M:%S.%6N UTC")` to preserve microseconds

## [0.4.0] - 2026-04-06
### Added
- **Bypass Default Scope Support**:
  - New `bypass_default_scope` configuration option for presets
  - When enabled, unscopes `default_scope` from all defined models during record collection
  - Ensures soft-deleted and other normally-hidden records are captured, preventing orphaned foreign key references in fixtures

## [0.3.18] - 2025-02-05
### Fixed
- Fixed cross-model circular dependency handling in PgDumpGenerator
  - The `prevent_circular_dependency` method previously only worked for self-referential associations (e.g., `ServiceRate → ServiceRate`) due to a guard clause (`assoc.klass == model`) in `build_dependency_graph`
  - Removed the self-referential constraint so `prevent_circular_dependency` now correctly breaks cycles between different models (e.g., `Organization → User → Organization`)

## [0.3.5 - 0.3.17] - 2025-01-14
### Fixed
- Enhanced SQL statement handling in native loader
  - Added proper UUID value quoting in VALUES clauses
  - Fixed string value formatting in SQL statements
  - Improved error reporting with detailed SQL statement context
  - Added robust SQL statement cleaning and normalization

## [0.3.4] - 2025-01-14
### Added
- Alternative native SQL loading method for CI environments
  - Added `load_real_test_data_native` method that doesn't rely on system commands
  - Works in restricted environments like GitHub Actions
  - Uses ActiveRecord's native connection for SQL execution
  - Maintains same transaction and foreign key handling behavior

## [0.3.3] - 2025-01-14
### Fixed
- Improved circular dependency handling in PgDumpGenerator for self-referential associations
  - Added robust checks for self-referential associations during topological sort
  - Updated dependency graph building to properly exclude prevented circular dependencies
  - Fixed model name handling in circular dependency error messages
  - Improved error reporting for circular dependency detection
- Enhanced PresetConfiguration circular dependency prevention
  - Added more reliable tracking of prevented reciprocal associations using Sets
  - Improved handling of both class and string model names in prevention checks
  - Better support for multiple prevented dependencies per model
- Updated record collection depth handling
  - Fixed max depth enforcement for nested associations
  - Added proper depth tracking for self-referential relationships
  - Improved interaction between max depth and circular dependency prevention

## [0.3.2] - 2025-01-14
### Fixed
- Enhanced association statistics tracking in RecordCollector
  - Added separate statistics tracking method to ensure accurate counts
  - Stats are now tracked before circular dependency checks
  - Fixed parent-child relationship counting in recursive associations
  - Improved initialization of statistics structures for better reliability

## [0.3.1] - 2025-01-14
### Fixed
- Fixed circular dependency handling in RecordCollector to correctly limit record collection
  - Moved prevention logic earlier in the collection process to stop circular dependencies before record collection
  - Improved tracking of visited associations for more accurate prevention
  - Added better logging for dependency prevention decisions
  - Fixed test case for circular dependency prevention in nested associations

## [0.3.0] - 2025-01-13
### Added
- **Polymorphic Association Support**:
  - RecordCollector now supports tracking and collecting records from polymorphic associations.
  - Polymorphic `belongs_to`, `has_many`, and `has_one` associations are automatically detected and processed during data collection.
  - Added tracking for polymorphic types in `@collection_stats` to provide detailed insights into polymorphic relationships.
  - Graceful handling of missing records in polymorphic associations using error logging.

### Fixed
- Improved error handling for `ActiveRecord::RecordNotFound` exceptions when loading polymorphic associations.
- Correctly initializes and updates association statistics for polymorphic associations in `@collection_stats`.

## [0.2.1] - 2025-01-13
### Fixed
- Fixed JSONB field handling to output '{}' instead of empty string for blank values
- Added test coverage for JSONB field handling in PgDumpGenerator

## [0.2.0] - 2025-01-13
### Added
- New preset system for managing different test data configurations
- Added `preset`, `use_preset`, and `with_preset` methods for configuration
- Support for multiple named configuration presets
- Added documentation for using presets
- New PresetConfig class to handle preset-specific configurations

### Changed
- Refactored Configuration class to use preset-based approach
- Moved configuration methods into PresetConfig class
- Updated documentation with preset usage examples and best practices

## [0.1.0] - 2025-01-11
- Initial release