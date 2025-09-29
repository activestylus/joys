# frozen_string_literal: true
# lib/joys/ssg.rb - Static Site Generation for hash-based data

require 'fileutils'
require 'json'
require 'set'
require 'digest'

module Joys
  module SSG
    module_function
    
    @output_dir = 'dist'
    @dependencies = { templates: {}, data: {} }
    @asset_manifest = {}
    @error_pages = {}
    
    class << self
      attr_accessor :output_dir
      attr_reader :dependencies, :asset_manifest, :error_pages
    end
    
    def build(content_dir, output_dir = @output_dir, force: false)
      #puts "Building static site: #{content_dir} → #{output_dir}"
      @dependencies = { templates: {}, data: {} }
      @asset_manifest = {}
      setup_output_dir(output_dir, force)
      load_data_definitions(content_dir)
      load_components_and_layouts(content_dir)
      pages = discover_pages(content_dir)
      built_files = build_pages(pages, output_dir, content_dir)
      build_error_pages(output_dir, content_dir)
      process_assets(content_dir, output_dir)
      save_dependencies(output_dir)
      save_asset_manifest(output_dir)
      #puts "Built #{built_files.size} pages"
      built_files
    end
    
    def build_incremental(content_dir, changed_files, output_dir = @output_dir)
      #puts "Incremental build for: #{changed_files.map { |f| File.basename(f) }.join(', ')}"
      load_dependencies(output_dir)
      load_asset_manifest(output_dir)
      affected_pages = find_affected_pages(changed_files)
      if affected_pages.empty?
        #puts "No pages affected by changes"
        return []
      end
      if changed_files.any? { |f| f.include?('/data/') }
        load_data_definitions(content_dir)
      end
      if changed_files.any? { |f| f.include?('/_components/') || f.include?('/_layouts/') }
        load_components_and_layouts(content_dir)
      end
      build_pages(affected_pages, output_dir, content_dir)
    end
    
    def setup_output_dir(output_dir, force)
      FileUtils.rm_rf(output_dir) if force && Dir.exist?(output_dir)
      FileUtils.mkdir_p(output_dir)
    end
    
    def load_data_definitions(content_dir)
      data_dir = File.join(content_dir, '../data')
      return unless Dir.exist?(data_dir)
      Joys::Data.configure(data_path: data_dir) if defined?(Joys::Data)
      Dir.glob("#{data_dir}/**/*_data.rb").each do |file|
        #puts "  Loading data: #{File.basename(file)}"
        load file
      end
    end
    
    def load_components_and_layouts(content_dir)
      Dir.glob("#{content_dir}/**/_components/*.rb").each do |file|
        #puts "  Loading component: #{File.basename(file, '.rb')}"
        load file
      end
      Dir.glob("#{content_dir}/**/_layouts/*.rb").each do |file|
        #puts "  Loading layout: #{File.basename(file, '.rb')}"
        load file
      end
    end
    
    def discover_pages(content_dir)
      pages = []
      error_pages = []
      
      Dir.glob("#{content_dir}/**/*.rb").each do |file|
        next if file.include?('/_components/') || 
                file.include?('/_layouts/')
        
        page_info = analyze_page_file(file, content_dir)
        next unless page_info
        
        # Check if this is an error page (404.rb, 500.rb, etc.)
        basename = File.basename(file, '.rb')
        if basename.match?(/^\d{3}$/) # HTTP status codes
          page_info[:error_code] = basename.to_i
          error_pages << page_info
        else
          pages << page_info
        end
      end
      
      # Store error pages for later use
      @error_pages = error_pages.group_by { |p| [p[:domain], p[:error_code]] }
      
      pages.compact
    end
    
    def analyze_page_file(file_path, content_dir)
      domain_match = file_path.match(%r{#{Regexp.escape(content_dir)}/([^/]+)/})
      return nil unless domain_match
      domain = domain_match[1]
      relative_path = file_path.sub("#{content_dir}/#{domain}/", '')
      url_path = file_path_to_url(relative_path)
      {
        file_path: file_path,
        domain: domain,
        url_path: url_path,
        output_path: url_to_output_path(domain, url_path)
      }
    end
    
    def file_path_to_url(file_path)
      path = file_path.sub(/\.rb$/, '')
      path = path == 'index' ? '/' : "/#{path}/"
      path.gsub(/_([^\/]+)/, ':\1')  # Convert _id to :id (though not used in SSG)
    end
    
    def url_to_output_path(domain, url_path)
      base = domain == 'default' ? '' : "#{domain}/"
      if url_path == '/'
        "#{base}index.html"
      else
        clean_path = url_path.gsub(/[^a-zA-Z0-9\/\-_]/, '')  # Remove special chars
        "#{base}#{clean_path.sub(/^\//, '').sub(/\/$/, '')}/index.html"
      end
    end
    
    def build_pages(pages, output_dir, content_dir)
      built_files = []
      pages.each do |page|
        page_results = build_single_page(page, content_dir)
        next if page_results.empty?
        
        page_results.each do |result|
          output_file = File.join(output_dir, result[:output_path])
          FileUtils.mkdir_p(File.dirname(output_file))
          File.write(output_file, result[:html])
          
          built_files << result[:output_path]
          #puts "  Built: #{result[:output_path]}"
        end
      end
      built_files
    end
    
    def build_single_page(page, content_dir)
      context = PageContext.new(page[:file_path], content_dir)
      begin
        source_code = File.read(page[:file_path])
        
        if source_code.include?('paginate')
          return build_paginated_pages(page, source_code, context, content_dir)
        else
          html = context.instance_eval(source_code, page[:file_path])
          
          @dependencies[:templates][page[:file_path]] = context.used_dependencies
          
          return [{ html: html, output_path: page[:output_path] }]
        end
      rescue => e
        #puts "  Error building #{page[:output_path]}: #{e.message}"
        return []
      end
    end
    
    def build_paginated_pages(page, source_code, context, content_dir)
      pages_generated = []
      context.setup_pagination_capture(page)
      context.instance_eval(source_code, page[:file_path])
      context.captured_paginations.each do |pagination|
        pagination[:pages].each_with_index do |page_obj, index|
          page_context = PageContext.new(page[:file_path], content_dir)
          page_context.current_pagination_page = page_obj
          
          html = page_context.instance_eval(pagination[:block_source], page[:file_path])
          
          output_path = generate_pagination_path(page[:output_path], index + 1)
          pages_generated << { html: html, output_path: output_path }
        end
      end
      @dependencies[:templates][page[:file_path]] = context.used_dependencies
      pages_generated
    end
    
    def generate_pagination_path(base_path, page_number)
      if page_number == 1
        base_path
      else
        base_path.sub(/\/index\.html$/, "/page-#{page_number}/index.html")
      end
    end
    
    def process_assets(content_dir, output_dir)
      # Copy global assets from public/ to root (no hashing)
      copy_global_assets(output_dir)
      
      # Process domain-specific assets with hashing
      process_domain_assets(content_dir, output_dir)
    end
    
    def copy_global_assets(output_dir)
      ['public', 'static'].each do |dir|
        next unless Dir.exist?(dir)
        Dir.glob("#{dir}/**/*").each do |file|
          next if File.directory?(file)
          
          relative = file.sub("#{dir}/", '')
          output_file = File.join(output_dir, relative)
          
          FileUtils.mkdir_p(File.dirname(output_file))
          FileUtils.cp(file, output_file)
          #puts "  Copied global asset: #{relative}"
        end
      end
    end
    
    def process_domain_assets(content_dir, output_dir)
      # Discover all domains
      domains = Dir.glob("#{content_dir}/*/").map { |d| File.basename(d) }
      
      domains.each do |domain|
        asset_dir = File.join(content_dir, domain, 'assets')
        next unless Dir.exist?(asset_dir)
        
        # Determine output path
        assets_output_dir = if domain == 'default'
          File.join(output_dir, 'assets')
        else
          File.join(output_dir, domain, 'assets')
        end
        
        FileUtils.mkdir_p(assets_output_dir)
        
        # Process each asset file
        Dir.glob("#{asset_dir}/**/*").each do |file|
          next if File.directory?(file)
          
          process_domain_asset(file, asset_dir, assets_output_dir, domain)
        end
      end
    end
    
    def process_domain_asset(file_path, asset_dir, output_dir, domain)
      # Get relative path within assets directory
      relative_path = file_path.sub("#{asset_dir}/", '')
      
      # Read file and generate hash
      content = File.read(file_path)
      hash = Digest::MD5.hexdigest(content)[0, 8]
      
      # Generate hashed filename
      ext = File.extname(relative_path)
      base = File.basename(relative_path, ext)
      dir = File.dirname(relative_path)
      
      hashed_filename = "#{base}-#{hash}#{ext}"
      hashed_relative = dir == '.' ? hashed_filename : "#{dir}/#{hashed_filename}"
      
      # Output file path
      output_file = File.join(output_dir, hashed_relative)
      FileUtils.mkdir_p(File.dirname(output_file))
      File.write(output_file, content)
      
      # Store in manifest
      manifest_key = "#{domain}/#{relative_path}"
      manifest_value = if domain == 'default'
        "/assets/#{hashed_relative}"
      else
        "/#{domain}/assets/#{hashed_relative}"
      end
      
      @asset_manifest[manifest_key] = manifest_value
      #puts "  Processed asset: #{manifest_key} → #{manifest_value}"
    end
    
    def save_dependencies(output_dir)
      deps_file = File.join(output_dir, '.ssg_dependencies.json')
      File.write(deps_file, JSON.pretty_generate(@dependencies))
    end
    
    def save_asset_manifest(output_dir)
      manifest_file = File.join(output_dir, '.asset_manifest.json')
      File.write(manifest_file, JSON.pretty_generate(@asset_manifest))
    end
    
    def load_dependencies(output_dir)
      deps_file = File.join(output_dir, '.ssg_dependencies.json')
      return unless File.exist?(deps_file)
      @dependencies = JSON.parse(File.read(deps_file))
    end
    
    def load_asset_manifest(output_dir)
      manifest_file = File.join(output_dir, '.asset_manifest.json')
      return unless File.exist?(manifest_file)
      @asset_manifest = JSON.parse(File.read(manifest_file))
    end
    
    def find_affected_pages(changed_files)
      affected = Set.new
      changed_files.each do |file|
        if file.include?('/_components/') || file.include?('/_layouts/')
          template_name = File.basename(file, '.rb')
          
          @dependencies['templates']&.each do |page_file, deps|
            if deps['components']&.include?(template_name) || 
               deps['layouts']&.include?(template_name)
              affected.add(page_file)
            end
          end
          
        elsif file.include?('/data/')
          data_name = File.basename(file, '_data.rb')
          
          @dependencies['data']&.dig(data_name)&.each do |page_file|
            affected.add(page_file)
          end
          
        elsif file.end_with?('.rb')
          affected.add(file)
        end
      end
      affected.map { |file| { file_path: file } }.compact
    end
    
    def build_error_pages(output_dir, content_dir)
      return if @error_pages.empty?
      
      @error_pages.each do |(domain, error_code), error_pages|
        error_page = error_pages.first # Take the first if multiple
        
        # Build the error page
        page_results = build_single_page(error_page, content_dir)
        next if page_results.empty?
        
        page_results.each do |result|
          # Save error pages with their status code names
          if domain == 'default'
            output_file = File.join(output_dir, "#{error_code}.html")
          else
            output_file = File.join(output_dir, domain, "#{error_code}.html")
          end
          
          FileUtils.mkdir_p(File.dirname(output_file))
          File.write(output_file, result[:html])
          
          #puts "  Built error page: #{error_code}.html (#{domain})"
        end
      end
    end
    
    def render_error_page(domain, error_code, context = {})
      # Find the appropriate error page
      error_page_info = @error_pages[[domain, error_code]]&.first
      error_page_info ||= @error_pages[['default', error_code]]&.first
      
      return nil unless error_page_info
      
      # Create a context with the error information
      page_context = PageContext.new(error_page_info[:file_path], File.dirname(error_page_info[:file_path]))
      
      # Assign context variables as locals (avoiding instance variable caveat)
      context.each do |key, value|
        page_context.instance_variable_set("@#{key}", value)
      end
      
      begin
        source_code = File.read(error_page_info[:file_path])
        page_context.instance_eval(source_code, error_page_info[:file_path])
      rescue => e
        #puts "  Error rendering error page #{error_code}: #{e.message}"
        nil
      end
    end
    
    class PageContext
      include Joys::Render::Helpers if defined?(Joys::Render::Helpers)
      include Joys::Tags if defined?(Joys::Tags)
      
      attr_reader :used_dependencies, :captured_paginations, :content_dir, :page_file_path
      attr_accessor :current_pagination_page
      
      def initialize(page_file_path, content_dir)
        @page_file_path = page_file_path
        @content_dir = content_dir
        @used_dependencies = { 'components' => [], 'layouts' => [], 'data' => [] }
        @captured_paginations = []
        @current_pagination_page = nil
        @bf = String.new  # Buffer for HTML output
        @slots = {}       # Slots for layout system
        
        # Load asset manifest for asset helpers
        manifest_file = File.join(SSG.output_dir, '.asset_manifest.json')
        @asset_manifest = if File.exist?(manifest_file)
          JSON.parse(File.read(manifest_file))
        else
          {}
        end
      end
      
      def setup_pagination_capture(page)
        @capturing_pagination = true
        @base_page = page
      end
      
      def params
        {}
      end
      
      def session
        {}
      end
      
      def html(&block)
        if defined?(Joys) && Joys.respond_to?(:html)
          Joys.html(&block)
        else
          yield if block_given?
        end
      end
      
      def layout(name, &block)
        @used_dependencies['layouts'] << name.to_s
        if defined?(Joys) && Joys.layouts.key?(name)
          layout_lambda = Joys.layouts[name]
          # Create a temporary buffer for the layout content
          old_bf = @bf
          @bf = String.new
          result = layout_lambda.call(self, &block)
          @bf = old_bf
          @bf << result if result
        else
          # Fallback for when Joys layout isn't available
          yield if block_given?
        end
      end
      
      def comp(name, *args)
        @used_dependencies['components'] << name.to_s
        if defined?(Joys) && Joys.respond_to?(:comp)
          Joys.comp(name, *args)
        else
          ""
        end
      end
      
      def data(model_name)
        @used_dependencies['data'] ||= []
        @used_dependencies['data'] << model_name.to_s
        
        SSG.dependencies[:data][model_name.to_s] ||= []
        SSG.dependencies[:data][model_name.to_s] << @page_file_path
        
        if defined?(Joys::Data)
          Joys::Data.query(model_name)
        else
          MockDataQuery.new
        end
      end
      
      # Asset helper methods
      def asset_path(asset_name)
        domain = extract_domain_from_path(@page_file_path)
        manifest_key = "#{domain}/#{asset_name}"
        
        @asset_manifest[manifest_key] || "/assets/#{asset_name}"
      end
      
      def asset_url(asset_name, base_url = nil)
        path = asset_path(asset_name)
        base_url ||= @site_url || ""
        base_url.chomp("/") + path
      end
      
      def paginate(collection, per_page:, &block)
        raise ArgumentError, "per_page must be positive" if per_page <= 0

        if collection.respond_to?(:paginate)
          # Use Joys::Data pagination if available
          pages = collection.paginate(per_page: per_page)
        else
          # Fallback for non-query collections (e.g., plain arrays)
          items = Array(collection)
          total_pages = (items.size.to_f / per_page).ceil
          pages = items.each_slice(per_page).map.with_index do |slice, index|
            Joys::Data::Page.new(slice, index + 1, total_pages, items.size)
          end
        end

        if @capturing_pagination
          @captured_paginations << {
            pages: pages,
            block_source: extract_block_source(block)
          }
          ""
        else
          if @current_pagination_page
            yield @current_pagination_page
          else
            ""
          end
        end
      end
      
      private
      
      def extract_domain_from_path(file_path)
        # Extract domain from path like content/blog_mysite_com/index.rb -> blog_mysite_com
        match = file_path.match(%r{#{Regexp.escape(@content_dir)}/([^/]+)/})
        match ? match[1] : 'default'
      end
      
      def create_page_object(items, current_page, total_pages, total_items, base_page)
        base_path = base_page[:url_path].chomp('/')
        base_path = '/' if base_path.empty?
        
        PageObject.new(
          posts: items,  # Using 'posts' for consistency with handoff doc
          current_page: current_page,
          total_pages: total_pages,
          total_items: total_items,
          prev_page: current_page > 1 ? current_page - 1 : nil,
          next_page: current_page < total_pages ? current_page + 1 : nil,
          prev_path: current_page > 1 ? (current_page == 2 ? base_path : "#{base_path}/page-#{current_page - 1}") : nil,
          next_path: current_page < total_pages ? "#{base_path}/page-#{current_page + 1}" : nil,
          is_first_page: current_page == 1,
          is_last_page: current_page == total_pages
        )
      end
      
      def extract_block_source(block)
        source_location = block.source_location
        if source_location
          file, line = source_location
          lines = File.readlines(file)
          lines[line - 1] || "yield page"
        else
          "yield page"
        end
      end
    end
    
    class PageObject
      def initialize(**attrs)
        @attrs = attrs
      end
      
      def method_missing(method_name, *args)
        if @attrs.key?(method_name)
          @attrs[method_name]
        else
          super
        end
      end
      
      def respond_to_missing?(method_name, include_private = false)
        @attrs.key?(method_name) || super
      end
      
      def to_h
        @attrs
      end
    end
    
    class MockDataQuery
      def method_missing(method, *args)
        self
      end
      
      def all
        []
      end
      
      def count
        0
      end
    end
  end
end

module Joys
  def self.build_static_site(content_dir, output_dir = 'dist', **options)
    SSG.build(content_dir, output_dir, **options)
  end
end