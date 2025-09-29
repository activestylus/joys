# frozen_string_literal: true
# lib/joys/data.rb - Ruby hash-based data querying

require 'json'
require 'date'

module Joys
  module Data
    # Custom error for data file issues
    class DataFileError < StandardError; end
    class ScopeError < StandardError; end
    class ItemMethodError < StandardError; end
    
    class << self
      def configure(data_path: 'data')
        @data_path = data_path
      end
      
      def define(model_name, &block)
        context = DefinitionContext.new(model_name, @data_path || 'data')
        context.instance_eval(&block)
        
        # Store the loaded data and methods
        @collections ||= {}
        @collections[model_name.to_sym] = {
          data: context.loaded_data,
          scopes: context.scopes,
          item_methods: context.item_methods
        }
      end
      
      def query(model_name)
        model_name = model_name.to_sym
        collection = @collections[model_name]
        
        unless collection
          raise "Collection #{model_name} not defined. Use Joys::Data.define :#{model_name} to define it."
        end
        
        Query.new(
          model_name, 
          collection[:data], 
          collection[:scopes], 
          collection[:item_methods]
        )
      end
      
      # Development helper methods
      def reload
        @collections = {}
      end
      
      def defined_models
        (@collections || {}).keys
      end
    end
    
    class DefinitionContext
      attr_reader :loaded_data, :scopes, :item_methods
      
      def initialize(model_name, data_path)
        @model_name = model_name
        @data_path = data_path
        @loaded_data = []
        @scopes = {}
        @item_methods = {}
      end
      
      def load(pattern)
        file_pattern = File.join(@data_path, pattern)
        files = Dir[file_pattern].sort
        
        if files.empty?
          raise "No files found matching pattern: #{file_pattern}"
        end
        
        @loaded_data = files.map do |file|
          begin
            # Each file should return a hash - evaluate in clean context
            hash_data = eval(File.read(file), TOPLEVEL_BINDING, file)
            unless hash_data.is_a?(::Hash)
              raise DataFileError, "#{file} should return a Hash, but returned #{hash_data.class}.\n\nMake sure your data file ends with a hash like:\n{\n  title: \"My Post\",\n  content: \"...\"\n}"
            end
            hash_data.freeze # Make immutable
          rescue DataFileError
            raise # Re-raise our custom errors as-is
          rescue SyntaxError => e
            raise DataFileError, "#{file} has a syntax error:\n#{e.message}\n\nCheck for missing commas, quotes, or brackets."
          rescue => e
            raise DataFileError, "#{file} couldn't be loaded:\n#{e.message}\n\nMake sure the file contains valid Ruby code that returns a Hash."
          end
        end
      end
      
      def from_array(array)
        unless array.is_a?(Array)
          raise DataFileError, "from_array() expects an Array of hashes, but got #{array.class}.\n\nExample:\nfrom_array([\n  { title: \"First Post\", content: \"...\" },\n  { title: \"Second Post\", content: \"...\" }\n])"
        end
        
        @loaded_data = array.map.with_index do |item, index|
          unless item.is_a?(::Hash)
            raise DataFileError, "from_array() array item #{index + 1} should be a Hash, but got #{item.class}.\n\nEach item in the array should look like:\n{ title: \"Post Title\", content: \"Post content\" }"
          end
          item.freeze # Make immutable
        end
      end
      
      def scope(methods_hash)
        methods_hash.each do |name, lambda_proc|
          unless lambda_proc.respond_to?(:call)
            raise "Scope #{name} must be callable (lambda or proc)"
          end
          @scopes[name.to_sym] = lambda_proc
        end
      end
      
      def item(methods_hash)
        methods_hash.each do |name, lambda_proc|
          unless lambda_proc.respond_to?(:call)
            raise "Item method #{name} must be callable (lambda or proc)"
          end
          @item_methods[name.to_sym] = lambda_proc
        end
      end
    end
    
    class Query
      include Enumerable
      
      def initialize(model_name, data, scopes, item_methods, conditions: [], order_field: nil, order_desc: false, limit_count: nil, offset_count: nil)
        @model_name = model_name
        @data = data
        @scopes = scopes
        @item_methods = item_methods
        @conditions = conditions
        @order_field = order_field
        @order_desc = order_desc
        @limit_count = limit_count
        @offset_count = offset_count
        
        # Dynamically define scope methods with better error context
        @scopes.each do |scope_name, scope_lambda|
          define_singleton_method(scope_name) do |*args|
            begin
              instance_exec(*args, &scope_lambda)
            rescue => e
              raise "Error in scope :#{scope_name} for model :#{@model_name}: #{e.message}\n  #{e.backtrace&.first}"
            end
          end
        end
      end
      
      # Core query methods
      def where(conditions)
        Query.new(@model_name, @data, @scopes, @item_methods,
                 conditions: @conditions + [conditions],
                 order_field: @order_field,
                 order_desc: @order_desc,
                 limit_count: @limit_count,
                 offset_count: @offset_count)
      end
      
      def order(field, desc: false)
        Query.new(@model_name, @data, @scopes, @item_methods,
                 conditions: @conditions,
                 order_field: field,
                 order_desc: desc,
                 limit_count: @limit_count,
                 offset_count: @offset_count)
      end
      
      def limit(count)
        Query.new(@model_name, @data, @scopes, @item_methods,
                 conditions: @conditions,
                 order_field: @order_field,
                 order_desc: @order_desc,
                 limit_count: count,
                 offset_count: @offset_count)
      end
      
      def offset(count)
        Query.new(@model_name, @data, @scopes, @item_methods,
                 conditions: @conditions,
                 order_field: @order_field,
                 order_desc: @order_desc,
                 limit_count: @limit_count,
                 offset_count: count)
      end
      
      # Terminal methods
      def all
        apply_filters.map { |hash| wrap_instance(hash) }
      end
      
      def first
        result = apply_filters.first
        result ? wrap_instance(result) : nil
      end
      
      def last
        result = apply_filters.last
        result ? wrap_instance(result) : nil
      end
      
      def count
        apply_filters.length
      end
      
      def find_by(conditions)
        where(conditions).first
      end
      
      # Enumerable support
      def each(&block)
        all.each(&block)
      end
      
      # Pagination support
      def paginate(per_page:)
        raise ArgumentError, "per_page must be positive" if per_page <= 0
        total_items = count
        return [Page.new([], 1, 1, total_items)] if total_items == 0
        total_pages = (total_items.to_f / per_page).ceil
        (1..total_pages).map do |page_num|
          offset_val = (page_num - 1) * per_page
          # Respect existing limits - don't override them
          items_per_page = if @limit_count && (@limit_count < per_page)
            # If existing limit is smaller than per_page, use the existing limit
            remaining_items = [@limit_count - offset_val, 0].max
            [remaining_items, per_page].min
          else
            per_page
          end
          items = self.offset(offset_val).limit(items_per_page).all
          Page.new(items, page_num, total_pages, total_items)
        end
      end
      
      private
      
      def apply_filters
        result = @data.dup
        
        # Apply conditions
        @conditions.each do |condition|
          result = result.select do |item|
            condition.all? do |field, value|
              evaluate_condition(item, field.to_sym, value) # Normalize field to symbol
            end
          end
        end
        
        # Apply ordering
        if @order_field
          # Separate nil values to always sort them to the end
          nil_items = result.select { |item| item[@order_field.to_sym].nil? }
          non_nil_items = result.reject { |item| item[@order_field.to_sym].nil? }
          
          # Sort non-nil items with proper type handling
          sorted_non_nil = non_nil_items.sort_by do |item|
            value = item[@order_field.to_sym]
            # Handle different types properly for sorting
            case value
            when Numeric
              [0, value]  # Numeric values first, keep as numeric
            when String
              [1, value]  # Strings second, keep as string
            when Date, Time
              [2, value]  # Dates third, keep as date
            else
              [3, value.to_s]  # Everything else as string
            end
          end
          
          # Combine: non-nil items + nil items (nil always at end)
          result = sorted_non_nil + nil_items
          
          # For descending, reverse only the non-nil portion
          if @order_desc
            result = sorted_non_nil.reverse + nil_items
          end
        end
        
        # Apply offset
        if @offset_count && @offset_count > 0
          result = result[@offset_count..-1] || []
        end
        
        # Apply limit
        if @limit_count
          result = result[0, @limit_count] || []
        end
        
        result
      end
      
      def evaluate_condition(item, field, value)
        field_value = item[field]
        
        case value
        when ::Hash
          if value.key?(:contains)
            field_value.to_s.include?(value[:contains].to_s)
          elsif value.key?(:starts_with)
            field_value.to_s.start_with?(value[:starts_with].to_s)
          elsif value.key?(:ends_with)
            field_value.to_s.end_with?(value[:ends_with].to_s)
          elsif value.key?(:greater_than)
            field_value && field_value > value[:greater_than]
          elsif value.key?(:less_than)
            field_value && field_value < value[:less_than]
          elsif value.key?(:greater_than_or_equal)
            field_value && field_value >= value[:greater_than_or_equal]
          elsif value.key?(:less_than_or_equal)
            field_value && field_value <= value[:less_than_or_equal]
          elsif value.key?(:from) && value.key?(:to)
            field_value && field_value >= value[:from] && field_value <= value[:to]
          elsif value.key?(:from)
            field_value && field_value >= value[:from]
          elsif value.key?(:to)
            field_value && field_value <= value[:to]
          elsif value.key?(:in)
            Array(value[:in]).include?(field_value)
          elsif value.key?(:not_in)
            !Array(value[:not_in]).include?(field_value)
          elsif value.key?(:not)
            field_value != value[:not]
          elsif value.key?(:exists)
            value[:exists] ? !field_value.nil? : field_value.nil?
          elsif value.key?(:empty)
            if value[:empty]
              field_value.nil? || field_value == '' || (field_value.respond_to?(:empty?) && field_value.empty?)
            else
              !field_value.nil? && field_value != '' && !(field_value.respond_to?(:empty?) && field_value.empty?)
            end
          else
            field_value == value
          end
        when Array
          if field_value.is_a?(Array)
            # For array fields, check if they contain the same elements
            field_value == value
          else
            # For non-array fields, check if field_value is in the array
            value.include?(field_value)
          end
        when Range
          value.include?(field_value)
        else
          field_value == value
        end
      end
      
      def wrap_instance(hash)
        InstanceWrapper.new(hash, @item_methods)
      end
    end
    
    class Page
      attr_reader :items, :current_page, :total_pages, :total_items,
                  :prev_page, :next_page, :is_first_page, :is_last_page
      
      def initialize(items, current_page, total_pages, total_items)
        @items = items
        @current_page = current_page
        @total_pages = total_pages
        @total_items = total_items
        @prev_page = current_page > 1 ? current_page - 1 : nil
        @next_page = current_page < total_pages ? current_page + 1 : nil
        @is_first_page = current_page == 1
        @is_last_page = current_page == total_pages
      end
      
      # Aliases for consistency with your SSG (e.g., 'posts' instead of 'items')
      alias_method :posts, :items
      
      def to_h
        {
          items: @items,
          current_page: @current_page,
          total_pages: @total_pages,
          total_items: @total_items,
          prev_page: @prev_page,
          next_page: @next_page,
          is_first_page: @is_first_page,
          is_last_page: @is_last_page
        }
      end
    end
    
    class InstanceWrapper
      def initialize(hash, item_methods)
        @hash = hash
        @item_methods = item_methods
        @memoized = {}
        
        # Dynamically define item methods with better error context
        @item_methods.each do |method_name, method_lambda|
          define_singleton_method(method_name) do |*args|
            # Memoize results to avoid recomputation
            cache_key = [method_name, args]
            
            unless @memoized.key?(cache_key)
              begin
                @memoized[cache_key] = instance_exec(*args, &method_lambda)
              rescue => e
                raise "Error in item method :#{method_name}: #{e.message}\n  #{e.backtrace&.first}"
              end
            end
            
            @memoized[cache_key]
          end
        end
      end
      
      # Hash-style access with symbol normalization
      def [](key)
        # Try symbol first, then string, then original key
        @hash[key.to_sym] || @hash[key]
      end
      
      def []=(key, value)
        raise "Joys::Data collections are immutable. Cannot assign #{key} = #{value}"
      end
      
      def has_key?(key)
        @hash.has_key?(key.to_sym) || @hash.has_key?(key.to_s)
      end
      
      def include?(key)
        @hash.include?(key.to_sym) || @hash.include?(key.to_s)
      end
      
      def key?(key)
        @hash.key?(key.to_sym) || @hash.key?(key.to_s)
      end
      
      def keys
        @hash.keys
      end
      
      def values  
        @hash.values
      end
      
      def to_h
        @hash
      end
      
      def to_hash
        @hash
      end
      
      # Make it behave like a hash for other operations
      def method_missing(method, *args, &block)
        if @hash.respond_to?(method)
          @hash.send(method, *args, &block)
        else
          super
        end
      end
      
      def respond_to_missing?(method, include_private = false)
        @hash.respond_to?(method, include_private) || super
      end
      
      def inspect
        "#<Joys::Data::Instance #{@hash.inspect}>"
      end
    end
  end
end

# Global helper method for cleaner syntax
def data(model_name)
  Joys::Data.query(model_name)
end
