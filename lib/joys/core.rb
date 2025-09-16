# frozen_string_literal: true
# lib/joys/core.rb
module Joys
  @css_path = "public/css";@cache={};@templates={};@compiled_styles={};@consolidated_cache={};@current_component = nil;@layouts={}
  class << self
    attr_reader :cache, :templates, :compiled_styles, :consolidated_cache, :layouts
    attr_accessor :current_component, :current_page, :css_path
  end
  def self.reset!
  @cache.clear
  @templates.clear
  @compiled_styles.clear
  @consolidated_cache.clear
  @layouts.clear
  @current_component = nil
  @current_page = nil
end

  def self.cache(cache_id, *args, &block);cache_key = [cache_id, args.hash];@cache[cache_key] ||= block.call;end
  def self.define(type, name, &template)
    full_name = "#{type}_#{name}";@templates[full_name] = template
    case type
    when :layout
      @layouts[name] = Joys::Render.layout(&template)
      define_singleton_method(full_name) { @layouts[name] }
    when :page
      define_singleton_method(full_name) do |**locals|
        old_component = @current_component
        old_page = @current_page
        @current_page = full_name
        @current_component = nil
        result = cache(full_name, locals.hash) do
          renderer = Object.new
          renderer.extend(Render::Helpers)
          renderer.extend(Tags)
          locals.each { |k, v| renderer.instance_variable_set("@#{k}", v) }
          renderer.instance_eval do
            @bf = String.new(capacity: 8192)
            @slots={}
            @used_components = Set.new
            @current_page = full_name    # Pass page context to renderer
          end
          renderer.instance_exec(&template)
          renderer.instance_variable_get(:@bf)
        end
        @current_component = old_component
        @current_page = old_page
        result.freeze
      end
    else
      define_singleton_method(full_name) do |*args|
        old_component = @current_component
        @current_component = full_name if type == :comp
        result = cache(full_name, *args) do
          Joys::Render.compile { instance_exec(*args, &template) }
        end
        @current_component = old_component
        result
      end
    end
  end
  def self.clear_cache!
    @cache.clear
    @compiled_styles.clear
    @consolidated_cache.clear
  end
  def self.page(name, **locals)
    page_name = "page_#{name}"
    renderer = Object.new
    renderer.extend(Render::Helpers)
    renderer.extend(Tags)
    locals.each { |k, v| renderer.instance_variable_set("@#{k}", v) }
    renderer.instance_eval do
      @bf = String.new(capacity: 8192)
      @slots={}
      @used_components = Set.new
      @current_page = page_name
      @used_components.add(page_name) if Joys.compiled_styles[page_name]
    end
    page_template = @templates[page_name]
    raise "No page template defined for #{name}" unless page_template
    old_page = @current_page
    @current_page = page_name
    renderer.instance_exec(&page_template)
    @current_page = old_page
    renderer.instance_variable_get(:@bf).freeze
  end
def self.comp(name, *args, **locals, &block)
  renderer = Object.new
  renderer.extend(Render::Helpers)
  renderer.extend(Tags)
  locals.each { |k, v| renderer.instance_variable_set("@#{k}", v) }
  renderer.instance_eval do
    @bf = String.new(capacity: 8192)
    @slots = {}
    @used_components = Set.new
  end
  
  comp_template = @templates["comp_#{name}"]
  raise "No comp template defined for #{name}" unless comp_template
  
  old_component = @current_component
  @current_component = "comp_#{name}"
  
  # Pass the block as a regular argument to the template
  renderer.instance_exec(*args, block, &comp_template)
  
  @current_component = old_component
  renderer.instance_variable_get(:@bf).freeze
end
  def self.html(&block)
    renderer = Object.new
    renderer.extend(Render::Helpers)
    renderer.extend(Tags)
    renderer.instance_variable_set(:@bf, String.new)
    
    # Only inherit page context for style compilation
    renderer.instance_variable_set(:@current_page, current_page) if current_page
    
    renderer.instance_eval(&block)
    renderer.instance_variable_get(:@bf)
  end
  module Render
    def self.compile(&block)
      context = Object.new;context.extend(Helpers);context.extend(Tags)
      context.instance_eval { @bf = String.new(capacity: 8192);@slots={};@used_components = Set.new}
      context.instance_eval(&block)
      context.instance_variable_get(:@bf).freeze
    end
    def self.layout(&layout_block)
      template = Object.new;template.extend(Helpers);template.extend(Tags)
      template.instance_eval { @bf = String.new;@slots={};@used_components = Set.new }
      template.define_singleton_method(:pull) { |name = :main| @bf << "<!--SLOT:#{name}-->"; nil }
      template.instance_eval(&layout_block)
      precompiled = template.instance_variable_get(:@bf).freeze
      ->(context, &content_block) {
        context.instance_eval(&content_block) if content_block
        slots = context.instance_variable_get(:@slots) || {}
        used_components = context.instance_variable_get(:@used_components)
        if used_components && !used_components.empty?
          auto_styles = Joys::Styles.render_consolidated_styles(used_components)
        else
          auto_styles = ""
        end
        slot_regex = /<!--SLOT:(.*?)-->/.freeze
        result = precompiled.gsub(slot_regex) do |match|
          slot_name = $1.to_sym
          slots[slot_name] || ""
        end
        if result.include?('<!--STYLES-->')
          result = result.gsub(/<!--STYLES-->/, auto_styles)
        end
        if result.include?('<!--EXTERNAL_STYLES-->')
          external_styles = Joys::Styles.render_external_styles(used_components)
          result = result.gsub(/<!--EXTERNAL_STYLES-->/, external_styles)
        end
        result
      }
    end
  end
end