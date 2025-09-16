require 'minitest/autorun'
require 'minitest/pride'
require_relative '../lib/joys/hash'  # Keep original path until file is renamed
require 'date'
require 'tmpdir'  # For temporary file tests
require 'fileutils'

module Joys
  module Data
    class TestJoysData < Minitest::Test
      def setup
        Joys::Data.reload  # Clear collections before each test
        # Reset data path to default
        Joys::Data.configure(data_path: 'data')
      end

      def teardown
        Joys::Data.reload  # Clean up after each test
      end

      def test_configure
        Joys::Data.configure(data_path: 'custom_data')
        assert_equal 'custom_data', Joys::Data.instance_variable_get(:@data_path)
      end

      def test_define_and_query
        Joys::Data.define :test_model do
          from_array([{ id: 1 }])
        end
        assert_instance_of Query, Joys::Data.query(:test_model)
      end

      def test_undefined_model_raises
        error = assert_raises(RuntimeError) { Joys::Data.query(:undefined) }
        assert_equal "Collection undefined not defined. Use Joys::Data.define :undefined to define it.", error.message
      end

      def test_reload
        Joys::Data.define :test_model do
          from_array([])
        end
        Joys::Data.reload
        assert_empty Joys::Data.defined_models
      end

      def test_defined_models
        Joys::Data.define :model1 do
          from_array([])
        end
        Joys::Data.define :model2 do
          from_array([])
        end
        assert_equal [:model1, :model2], Joys::Data.defined_models.sort
      end

      def test_global_helper
        Joys::Data.define :test_model do
          from_array([{ id: 1 }])
        end
        
        # Test the global data() helper method
        assert_instance_of Query, data(:test_model)
      end
    end

    class TestDefinitionContext < Minitest::Test
      def setup
        @context = DefinitionContext.new(:test_model, 'data')
      end

      def test_from_array_with_valid_array
        @context.from_array([{ id: 1, name: 'Test' }, { id: 2, name: 'Another' }])
        assert_equal 2, @context.loaded_data.size
        assert @context.loaded_data.all?(&:frozen?)
      end

      def test_from_array_with_non_array
        error = assert_raises(DataFileError) { @context.from_array('not an array') }
        assert_match /expects an Array of hashes, but got String/, error.message
      end

      def test_from_array_with_non_hash_item
        error = assert_raises(DataFileError) { @context.from_array(['not a hash']) }
        assert_match /array item 1 should be a Hash, but got String/, error.message
      end

      def test_scope_definition
        @context.scope({ test_scope: -> { self } })
        assert @context.scopes.key?(:test_scope)
      end

      def test_scope_non_callable
        assert_raises(RuntimeError) { @context.scope({ test_scope: 'not callable' }) }
      end

      def test_item_definition
        @context.item({ test_method: -> { 'value' } })
        assert @context.item_methods.key?(:test_method)
      end

      def test_item_non_callable
        assert_raises(RuntimeError) { @context.item({ test_method: 'not callable' }) }
      end

      def test_load_with_files
        Dir.mktmpdir do |dir|
          # Create test files
          File.write(File.join(dir, 'file1.rb'), "{ id: 1, title: 'First' }")
          File.write(File.join(dir, 'file2.rb'), "{ id: 2, title: 'Second' }")
          
          context = DefinitionContext.new(:test, dir)
          context.load('*.rb')
          
          assert_equal 2, context.loaded_data.size
          assert_equal({ id: 1, title: 'First' }, context.loaded_data[0])
          assert_equal({ id: 2, title: 'Second' }, context.loaded_data[1])
          assert context.loaded_data.all?(&:frozen?)
        end
      end

      def test_load_no_files
        Dir.mktmpdir do |dir|
          context = DefinitionContext.new(:test, dir)
          error = assert_raises(RuntimeError) { context.load('*.rb') }
          assert_match /No files found matching pattern/, error.message
        end
      end

      def test_load_non_hash
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, 'invalid.rb'), "'string'")
          context = DefinitionContext.new(:test, dir)
          error = assert_raises(DataFileError) { context.load('*.rb') }
          assert_match /should return a Hash, but returned String/, error.message
        end
      end

      def test_load_syntax_error
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, 'invalid.rb'), "{ id: 1,, }")  # Actual syntax error - double comma
          context = DefinitionContext.new(:test, dir)
          error = assert_raises(DataFileError) { context.load('*.rb') }
          assert_match /has a syntax error/, error.message
        end
      end

      def test_load_generic_error
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, 'error.rb'), "raise 'boom'")
          context = DefinitionContext.new(:test, dir)
          error = assert_raises(DataFileError) { context.load('*.rb') }
          assert_match /couldn't be loaded:\nboom/, error.message
        end
      end
    end

    class TestQuery < Minitest::Test
      def setup
        Joys::Data.reload
        Joys::Data.define :posts do
          from_array([
            { id: 1, title: 'Post 1', published_at: Date.new(2024, 1, 1), featured: true, tags: ['ruby', 'web'], views: 100 },
            { id: 2, title: 'Post 2', published_at: Date.new(2024, 2, 1), featured: false, tags: ['tools'], views: 200 },
            { id: 3, title: 'Post 3', published_at: Date.new(2023, 12, 1), featured: true, tags: ['ruby'], views: 150 },
            { id: 4, title: nil, published_at: nil, featured: nil, tags: [], views: nil }
          ])

          scope({
            featured: -> { where(featured: true) },
            recent: ->(n=2) { order(:published_at, desc: true).limit(n) },
            tagged: ->(tag) { where(tags: { contains: tag }) }
          })

          item({
            title_upper: -> { self[:title]&.upcase },
            view_category: -> { self[:views] && self[:views] > 150 ? 'popular' : 'standard' }
          })
        end
        @query = Joys::Data.query(:posts)
      end

      def teardown
        Joys::Data.reload
      end

      def test_all
        assert_equal 4, @query.all.size
        assert @query.all.all? { |item| item.is_a?(InstanceWrapper) }
      end

      def test_first_and_last
        assert_equal 1, @query.first[:id]
        assert_equal 4, @query.last[:id]
      end

      def test_count
        assert_equal 4, @query.count
      end

      def test_find_by
        post = @query.find_by(id: 2)
        assert_equal 'Post 2', post[:title]
      end

      def test_where_equality
        results = @query.where(featured: true).all
        assert_equal [1, 3], results.map { |p| p[:id] }.sort
      end

      def test_where_hash_conditions
        results = @query.where(title: { contains: 'Post' }).all
        assert_equal 3, results.size

        results = @query.where(published_at: { greater_than: Date.new(2024, 1, 1) }).all
        assert_equal [2], results.map { |p| p[:id] }

        results = @query.where(published_at: { less_than: Date.new(2024, 1, 1) }).all
        assert_equal [3], results.map { |p| p[:id] }

        results = @query.where(published_at: { greater_than_or_equal: Date.new(2024, 1, 1) }).all
        assert_equal [1, 2], results.map { |p| p[:id] }.sort

        results = @query.where(published_at: { less_than_or_equal: Date.new(2024, 1, 1) }).all
        assert_equal [1, 3], results.map { |p| p[:id] }.sort

        results = @query.where(published_at: { from: Date.new(2024, 1, 1), to: Date.new(2024, 2, 1) }).all
        assert_equal [1, 2], results.map { |p| p[:id] }.sort

        results = @query.where(published_at: { from: Date.new(2024, 1, 1) }).all
        assert_equal [1, 2], results.map { |p| p[:id] }.sort

        results = @query.where(published_at: { to: Date.new(2024, 1, 1) }).all
        assert_equal [1, 3], results.map { |p| p[:id] }.sort

        results = @query.where(id: { in: [1, 3] }).all
        assert_equal [1, 3], results.map { |p| p[:id] }.sort

        results = @query.where(id: { not_in: [1, 3] }).all
        assert_equal [2, 4], results.map { |p| p[:id] }.sort

        results = @query.where(featured: { not: true }).all
        assert_equal [2, 4], results.map { |p| p[:id] }.sort  # Both false and nil are "not true"

        results = @query.where(tags: { empty: true }).all
        assert_equal [4], results.map { |p| p[:id] }

        results = @query.where(tags: { empty: false }).all
        assert_equal [1, 2, 3], results.map { |p| p[:id] }.sort

        results = @query.where(title: { exists: true }).all
        assert_equal 3, results.size

        results = @query.where(title: { exists: false }).all
        assert_equal [4], results.map { |p| p[:id] }

        results = @query.where(title: { starts_with: 'Post' }).all
        assert_equal 3, results.size

        results = @query.where(title: { ends_with: '1' }).all
        assert_equal [1], results.map { |p| p[:id] }
      end

      def test_where_array
        results = @query.where(id: [1, 3]).all
        assert_equal [1, 3], results.map { |p| p[:id] }.sort
      end

      def test_where_range
        results = @query.where(published_at: Date.new(2024, 1, 1)..Date.new(2024, 12, 31)).all
        assert_equal [1, 2], results.map { |p| p[:id] }.sort
      end

      def test_order_asc
        results = @query.order(:published_at).all
        # nil values should sort to the end
        expected_order = [3, 1, 2, 4] # 2023-12-01, 2024-01-01, 2024-02-01, nil
        assert_equal expected_order, results.map { |p| p[:id] }
      end

      def test_order_desc
        results = @query.order(:published_at, desc: true).all
        # With desc=true, non-nil values are reversed, nil still at end
        expected_order = [2, 1, 3, 4] # 2024-02-01, 2024-01-01, 2023-12-01, nil
        assert_equal expected_order, results.map { |p| p[:id] }
      end

      def test_limit_and_offset
        results = @query.order(:id).limit(2).all
        assert_equal [1, 2], results.map { |p| p[:id] }

        results = @query.order(:id).offset(2).limit(1).all
        assert_equal [3], results.map { |p| p[:id] }

        results = @query.order(:id).offset(1).limit(2).all
        assert_equal [2, 3], results.map { |p| p[:id] }

        # Test offset beyond array bounds
        results = @query.order(:id).offset(10).all
        assert_equal [], results.map { |p| p[:id] }
      end

      def test_chained_queries
        # Test complex chaining
        results = @query.where(featured: true).order(:published_at, desc: true).limit(1).all
        assert_equal [1], results.map { |p| p[:id] } # Most recent featured post

        results = @query.where(views: { greater_than: 120 }).where(featured: true).all
        assert_equal [3], results.map { |p| p[:id] }
      end

      def test_scopes
        featured = @query.featured.all
        assert_equal [1, 3], featured.map { |p| p[:id] }.sort

        recent = @query.recent.all
        assert_equal [2, 1], recent.map { |p| p[:id] }

        recent_3 = @query.recent(3).all
        assert_equal [2, 1, 3], recent_3.map { |p| p[:id] }

        tagged = @query.tagged('ruby').all
        assert_equal [1, 3], tagged.map { |p| p[:id] }.sort

        # Test scope chaining
        featured_ruby = @query.featured.tagged('ruby').all
        assert_equal [1, 3], featured_ruby.map { |p| p[:id] }.sort
      end

      def test_scope_error_handling
        Joys::Data.define :error_model do
          from_array([])
          scope({ bad: -> { raise 'boom' } })
        end
        query = Joys::Data.query(:error_model)
        error = assert_raises(RuntimeError) { query.bad }
        assert_match /Error in scope :bad for model :error_model: boom/, error.message
      end

      def test_enumerable
        assert_equal 4, @query.map { |p| p[:id] }.size
        
        # Test other enumerable methods
        titles = @query.select { |p| p[:title] }.map { |p| p[:title] }
        assert_equal ['Post 1', 'Post 2', 'Post 3'], titles.sort

        featured_ids = @query.select { |p| p[:featured] }.map { |p| p[:id] }
        assert_equal [1, 3], featured_ids.sort

        assert @query.any? { |p| p[:featured] }
        assert @query.all? { |p| p[:id].is_a?(Integer) }
      end

      def test_symbol_normalization_in_conditions
        results = @query.where('featured' => true).all  # String key
        assert_equal 2, results.size

        # Test mixed symbol/string keys
        results = @query.where('id' => 1, :featured => true).all
        assert_equal [1], results.map { |p| p[:id] }
      end

      def test_complex_conditions
        # Test conditions that evaluate to false/nil
        results = @query.where(featured: false).all
        assert_equal [2], results.map { |p| p[:id] }

        results = @query.where(featured: nil).all
        assert_equal [4], results.map { |p| p[:id] }

        # Test with exact array matching
        results = @query.where(tags: ['ruby', 'web']).all
        assert_equal [1], results.map { |p| p[:id] }
        
        # Test with different array
        results = @query.where(tags: ['tools']).all
        assert_equal [2], results.map { |p| p[:id] }
      end
    end

    class TestInstanceWrapper < Minitest::Test
      def setup
        @hash = { id: 1, title: 'Test', content: 'Long content here for testing purpose', views: 100, published_at: Date.new(2024, 1, 1) }.freeze
        @item_methods = {
          excerpt: ->(words=2) { self[:content].split.take(words).join(' ') + '...' },
          title_upper: -> { self[:title].upcase },
          formatted_date: -> { self[:published_at]&.strftime("%B %d, %Y") },
          view_category: -> { self[:views] && self[:views] > 150 ? 'popular' : 'standard' },
          word_count: -> { self[:content].split.size },
          summary: ->(max_words=10) { 
            words = self[:content].split.take(max_words)
            "#{words.join(' ')}#{words.size >= max_words ? '...' : ''}"
          }
        }
        @wrapper = InstanceWrapper.new(@hash, @item_methods)
      end

      def test_hash_access
        assert_equal 1, @wrapper[:id]
        assert_equal 'Test', @wrapper[:title]
        assert_equal 'Test', @wrapper['title']  # String key should also work
        assert_equal 100, @wrapper[:views]
        assert_nil @wrapper[:non_existent]
      end

      def test_symbol_string_key_normalization
        # Should work with both symbols and strings
        assert_equal 'Test', @wrapper[:title]
        assert_equal 'Test', @wrapper['title']
        assert_equal 1, @wrapper[:id]
        assert_equal 1, @wrapper['id']
      end

      def test_immutability
        error = assert_raises(RuntimeError) { @wrapper[:id] = 2 }
        assert_match /immutable/, error.message
        
        error = assert_raises(RuntimeError) { @wrapper['title'] = 'New Title' }
        assert_match /immutable/, error.message
      end

      def test_item_methods
        assert_equal 'Long content...', @wrapper.excerpt
        assert_equal 'Long...', @wrapper.excerpt(1)
        assert_equal 'Long content here...', @wrapper.excerpt(3)
        assert_equal 'TEST', @wrapper.title_upper
        assert_equal 'January 01, 2024', @wrapper.formatted_date
        assert_equal 'standard', @wrapper.view_category
        assert_equal 6, @wrapper.word_count  # "Long content here for testing purpose" = 6 words
      end

      def test_item_methods_with_parameters
        # Test method with different parameter values
        assert_equal 'Long content...', @wrapper.excerpt(2)
        assert_equal 'Long content here for...', @wrapper.excerpt(4)
        
        assert_equal 'Long content here for testing...', @wrapper.summary(5)
        assert_equal 'Long content here for testing purpose', @wrapper.summary(10) # No ellipsis when all words fit
      end

      def test_memoization
        # Call the same method twice to ensure memoization works
        result1 = @wrapper.excerpt
        result2 = @wrapper.excerpt
        assert_equal result1, result2
        assert_equal 'Long content...', result1
        
        # Different parameters should not be memoized together
        result3 = @wrapper.excerpt(1)
        assert_equal 'Long...', result3
        refute_equal result1, result3
        
        # Same parameters should be memoized
        result4 = @wrapper.excerpt(1)
        assert_equal result3, result4
        
        # Test memoization with different methods
        date1 = @wrapper.formatted_date
        date2 = @wrapper.formatted_date
        assert_equal date1, date2
        assert_equal 'January 01, 2024', date1
      end

      def test_item_method_with_nil_handling
        nil_hash = { id: 1, title: nil, content: nil, published_at: nil }.freeze
        nil_methods = {
          safe_title: -> { self[:title] || 'Untitled' },
          safe_date: -> { self[:published_at]&.strftime("%Y-%m-%d") || 'No date' },
          content_length: -> { (self[:content] || '').length }
        }
        wrapper = InstanceWrapper.new(nil_hash, nil_methods)
        
        assert_equal 'Untitled', wrapper.safe_title
        assert_equal 'No date', wrapper.safe_date
        assert_equal 0, wrapper.content_length
      end

      def test_item_method_error
        error_methods = {
          bad: -> { raise 'boom' },
          another_bad: -> { undefined_method_call }
        }
        wrapper = InstanceWrapper.new(@hash, error_methods)
        
        error = assert_raises(RuntimeError) { wrapper.bad }
        assert_match /Error in item method :bad: boom/, error.message
        
        error = assert_raises(RuntimeError) { wrapper.another_bad }
        assert_match /Error in item method :another_bad/, error.message
      end

      def test_hash_methods
        expected_keys = [:id, :title, :content, :views, :published_at]
        assert_equal expected_keys.sort, @wrapper.keys.sort
        assert_equal @hash, @wrapper.to_h
        assert_equal @hash, @wrapper.to_hash
        # Don't sort values since they may be of different types
        assert_equal @hash.values.size, @wrapper.values.size
      end

      def test_method_missing_for_hash
        assert_equal 5, @wrapper.size  # Hash#size
        assert @wrapper.has_key?(:id)
        assert @wrapper.has_key?('title')
        refute @wrapper.has_key?(:non_existent)
        
        # Test other hash methods
        assert @wrapper.include?(:id)
        assert_equal @hash.length, @wrapper.length
        
        # Just test that size > 0 instead of testing empty? directly
        assert @wrapper.size > 0
      end

      def test_respond_to_missing
        assert @wrapper.respond_to?(:keys)
        assert @wrapper.respond_to?(:size)
        assert @wrapper.respond_to?(:has_key?)
        assert @wrapper.respond_to?(:include?)
        assert @wrapper.respond_to?(:empty?)
        
        # Test item methods
        assert @wrapper.respond_to?(:excerpt)
        assert @wrapper.respond_to?(:title_upper)
        assert @wrapper.respond_to?(:formatted_date)
        
        refute @wrapper.respond_to?(:non_existent_method)
      end

      def test_inspect
        assert_match /#<Joys::Data::Instance {.*}>/, @wrapper.inspect
        assert_match /id.*1/, @wrapper.inspect
        assert_match /title.*"Test"/, @wrapper.inspect
      end

      def test_complex_item_methods
        complex_hash = { 
          tags: ['ruby', 'web', 'programming'], 
          metadata: { author: 'John', category: 'tech' },
          scores: [85, 90, 78, 92]
        }.freeze
        
        complex_methods = {
          tag_list: -> { self[:tags].join(', ') },
          author_name: -> { self[:metadata][:author] },
          average_score: -> { self[:scores].sum.to_f / self[:scores].length },
          top_score: -> { self[:scores].max },
          tag_count: -> { self[:tags].length }
        }
        
        wrapper = InstanceWrapper.new(complex_hash, complex_methods)
        
        assert_equal 'ruby, web, programming', wrapper.tag_list
        assert_equal 'John', wrapper.author_name
        assert_equal 86.25, wrapper.average_score
        assert_equal 92, wrapper.top_score
        assert_equal 3, wrapper.tag_count
      end
    end

    class TestEdgeCases < Minitest::Test
      def setup
        Joys::Data.reload
      end

      def teardown
        Joys::Data.reload
      end

      def test_empty_collections
        Joys::Data.define :empty do
          from_array([])
        end

        query = Joys::Data.query(:empty)
        assert_equal 0, query.count
        assert_equal [], query.all
        assert_nil query.first
        assert_nil query.last
        assert_equal [], query.where(id: 1).all
        assert_equal [], query.order(:id).all
        assert_equal [], query.limit(5).all
        assert_equal [], query.offset(2).all
      end

      def test_single_item_collection
        Joys::Data.define :single do
          from_array([{ id: 1, title: 'Only One' }])
        end

        query = Joys::Data.query(:single)
        assert_equal 1, query.count
        assert_equal 1, query.first[:id]
        assert_equal 1, query.last[:id]
        assert_equal [1], query.all.map { |item| item[:id] }
      end

      def test_collections_with_duplicate_data
        Joys::Data.define :duplicates do
          from_array([
            { id: 1, name: 'John' },
            { id: 2, name: 'John' },
            { id: 3, name: 'John' }
          ])
        end

        query = Joys::Data.query(:duplicates)
        johns = query.where(name: 'John').all
        assert_equal 3, johns.size
        assert_equal [1, 2, 3], johns.map { |item| item[:id] }.sort
      end

      def test_collections_with_all_nils
        Joys::Data.define :nils do
          from_array([
            { id: 1, value: nil },
            { id: 2, value: nil },
            { id: 3, value: nil }
          ])
        end

        query = Joys::Data.query(:nils)
        results = query.where(value: { exists: false }).all
        assert_equal 3, results.size

        results = query.where(value: { empty: true }).all
        assert_equal 3, results.size
      end

      def test_large_offset_and_limit
        Joys::Data.define :numbers do
          from_array((1..100).map { |n| { id: n, value: n * 2 } })
        end

        query = Joys::Data.query(:numbers)
        
        # Test large offset beyond collection size
        results = query.offset(200).all
        assert_equal [], results

        # Test large limit on small remaining items
        results = query.offset(95).limit(10).all
        assert_equal 5, results.size # Only 5 items left after offset 95

        # Test zero limit
        results = query.limit(0).all
        assert_equal [], results

        # Test negative offset (should be treated as 0)
        results = query.offset(-5).limit(3).all
        assert_equal 3, results.size
      end

      def test_complex_chaining_with_no_results
        Joys::Data.define :complex do
          from_array([
            { id: 1, category: 'A', published: true, views: 100 },
            { id: 2, category: 'B', published: false, views: 200 }
          ])
        end

        query = Joys::Data.query(:complex)
        
        # Chain filters that result in no matches
        results = query.where(category: 'A').where(published: false).all
        assert_equal [], results

        results = query.where(views: { greater_than: 300 }).all
        assert_equal [], results

        results = query.where(id: [10, 20, 30]).all
        assert_equal [], results
      end

      def test_scope_with_parameters_edge_cases
        Joys::Data.define :parameterized do
          from_array([
            { id: 1, score: 85 },
            { id: 2, score: 92 },
            { id: 3, score: 78 },
            { id: 4, score: 95 }
          ])

          scope({
            by_score: ->(min_score) { where(score: { greater_than_or_equal: min_score }) },
            top_n: ->(n) { order(:score, desc: true).limit(n) },
            score_range: ->(min, max) { where(score: { from: min, to: max }) }
          })
        end

        query = Joys::Data.query(:parameterized)
        
        # Test with edge case parameters
        results = query.by_score(100).all  # No matches
        assert_equal [], results

        results = query.by_score(0).all    # All matches
        assert_equal 4, results.size

        results = query.top_n(0).all       # Empty limit
        assert_equal [], results

        results = query.score_range(90, 100).all  # Small range
        assert_equal [2, 4], results.map { |item| item[:id] }.sort
      end

      def test_method_name_conflicts
        # Test that our methods don't conflict with Ruby built-ins
        Joys::Data.define :conflicts do
          from_array([{ id: 1, hash: 'test_hash', class: 'test_class' }])
        end

        query = Joys::Data.query(:conflicts)
        item = query.first
        
        # These should work fine
        assert_equal 'test_hash', item[:hash]
        assert_equal 'test_class', item[:class]
        
        # These should be the Ruby built-ins
        assert item.hash.is_a?(Integer)  # Ruby's Object#hash
        assert_equal InstanceWrapper, item.class  # Ruby's Object#class
      end

      def test_ordering_with_mixed_types
        # Test ordering when values are of different types (should handle gracefully)
        Joys::Data.define :mixed do
          from_array([
            { id: 1, value: 'string' },
            { id: 2, value: 42 },
            { id: 3, value: nil },
            { id: 4, value: Date.new(2024, 1, 1) }
          ])
        end

        query = Joys::Data.query(:mixed)
        
        # Should not raise an error, even with mixed types
        results = query.order(:value).all
        assert_equal 4, results.size
        
        # nil should be at the end
        assert_equal 3, results.last[:id]
      end
    end

    class TestPagination < Minitest::Test
      def setup
        Joys::Data.reload
        # Create a collection with 23 items for thorough pagination testing
        Joys::Data.define :paginated_posts do
          from_array((1..23).map do |i|
            { 
              id: i, 
              title: "Post #{i}", 
              content: "Content for post #{i}",
              priority: i % 3,  # 0, 1, 2, 0, 1, 2, ...
              published: i <= 20 # First 20 are published
            }
          end)

          scope({
            published: -> { where(published: true) },
            by_priority: ->(p) { where(priority: p) }
          })

          item({
            slug: -> { "post-#{self[:id]}" },
            excerpt: -> { "#{self[:content][0..20]}..." }
          })
        end
        @query = Joys::Data.query(:paginated_posts)
      end

      def teardown
        Joys::Data.reload
      end

      def test_basic_pagination
        pages = @query.paginate(per_page: 5)
        
        # Should have 5 pages (23 items / 5 per page = 4.6, rounded up to 5)
        assert_equal 5, pages.length
        
        # Test first page
        first_page = pages.first
        assert_instance_of Joys::Data::Page, first_page
        assert_equal 5, first_page.items.size
        assert_equal 1, first_page.current_page
        assert_equal 5, first_page.total_pages
        assert_equal 23, first_page.total_items
        assert_nil first_page.prev_page
        assert_equal 2, first_page.next_page
        assert first_page.is_first_page
        refute first_page.is_last_page
        
        # Test middle page
        middle_page = pages[2] # Page 3
        assert_equal 5, middle_page.items.size
        assert_equal 3, middle_page.current_page
        assert_equal 2, middle_page.prev_page
        assert_equal 4, middle_page.next_page
        refute middle_page.is_first_page
        refute middle_page.is_last_page
        
        # Test last page (should have only 3 items: 21, 22, 23)
        last_page = pages.last
        assert_equal 3, last_page.items.size
        assert_equal 5, last_page.current_page
        assert_equal 4, last_page.prev_page
        assert_nil last_page.next_page
        refute last_page.is_first_page
        assert last_page.is_last_page
      end

      def test_pagination_with_chaining
        # Test pagination with where conditions
        published_pages = @query.published.paginate(per_page: 8)
        
        # Should have 3 pages (20 published items / 8 per page = 2.5, rounded up to 3)
        assert_equal 3, published_pages.length
        assert_equal 20, published_pages.first.total_items
        
        # Debug the descending order issue
        ordered_query = @query.order(:id, desc: true)
        
        ordered_pages = ordered_query.paginate(per_page: 6)
        first_page_items = ordered_pages.first.items
        expected_ids = [23, 22, 21, 20, 19, 18]
        assert_equal expected_ids, first_page_items.map { |item| item[:id] }
        
        # Test pagination with scopes
        priority_pages = @query.by_priority(1).paginate(per_page: 3)
        # Priority 1 items: 1, 4, 7, 10, 13, 16, 19, 22 (8 items total)
        assert_equal 3, priority_pages.length  # 8 items / 3 per page = 2.67, rounded up to 3
        assert_equal 8, priority_pages.first.total_items
      end

      def test_single_page_collection
        # Apply limit first, then paginate the limited results
        limited_query = @query.limit(5)
        small_pages = limited_query.paginate(per_page: 10)
        
        assert_equal 1, small_pages.length
        page = small_pages.first
        assert_equal 5, page.items.size
        assert_equal 1, page.current_page
        assert_equal 1, page.total_pages
        assert_equal 5, page.total_items
        assert_nil page.prev_page
        assert_nil page.next_page
        assert page.is_first_page
        assert page.is_last_page
      end

      def test_empty_collection_pagination
        empty_pages = @query.where(id: 999).paginate(per_page: 5)
        
        assert_equal 1, empty_pages.length
        page = empty_pages.first
        assert_equal [], page.items
        assert_equal 1, page.current_page
        assert_equal 1, page.total_pages
        assert_equal 0, page.total_items
      end

      def test_pagination_error_handling
        # Test with invalid per_page values
        error = assert_raises(ArgumentError) { @query.paginate(per_page: 0) }
        assert_match /per_page must be positive/, error.message
        
        error = assert_raises(ArgumentError) { @query.paginate(per_page: -5) }
        assert_match /per_page must be positive/, error.message
      end

      def test_page_object_methods
        pages = @query.paginate(per_page: 7)
        page = pages[1] # Second page
        
        # Test item methods work on paginated items
        first_item = page.items.first
        assert_equal "post-#{first_item[:id]}", first_item.slug
        assert_match /Content for post \d+\.\.\./, first_item.excerpt
        
        # Test posts alias
        assert_equal page.items, page.posts
        
        # Test to_h method
        page_hash = page.to_h
        expected_keys = [:items, :current_page, :total_pages, :total_items, 
                        :prev_page, :next_page, :is_first_page, :is_last_page]
        assert_equal expected_keys.sort, page_hash.keys.sort
        assert_equal page.current_page, page_hash[:current_page]
        assert_equal page.total_items, page_hash[:total_items]
        assert_equal page.is_first_page, page_hash[:is_first_page]
      end

      def test_pagination_maintains_order
        # Test that pagination preserves ordering - but our implementation only supports single field sorting
        ordered_pages = @query.order(:id).paginate(per_page: 6)
        
        all_items = []
        ordered_pages.each { |page| all_items.concat(page.items) }
        
        # Should maintain ID ordering across pages (1,2,3,4,5,6,7,8,9,10...)
        ids = all_items.map { |item| item[:id] }
        assert_equal (1..23).to_a, ids
      end

      def test_pagination_edge_cases
        # Test with per_page exactly equal to total items
        exact_pages = @query.limit(10).paginate(per_page: 10)
        assert_equal 1, exact_pages.length
        assert_equal 10, exact_pages.first.items.size
        
        # Test with per_page larger than total items - limit to 3 items first
        limited_query = @query.limit(3)
        large_pages = limited_query.paginate(per_page: 10)
        assert_equal 1, large_pages.length
        assert_equal 3, large_pages.first.items.size
        assert_equal 3, large_pages.first.total_items  # Total should also be 3
        
        # Test with per_page = 1 (maximum pages) - limit to 5 items first
        limited_query_5 = @query.limit(5)
        single_pages = limited_query_5.paginate(per_page: 1)
        assert_equal 5, single_pages.length
        assert_equal 5, single_pages.first.total_items  # Total should be 5
        single_pages.each_with_index do |page, index|
          assert_equal 1, page.items.size
          assert_equal index + 1, page.current_page
          assert_equal 5, page.total_pages
        end
      end
    end
  end
end