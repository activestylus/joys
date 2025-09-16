# frozen_string_literal: true
# lib/joys/styles.rb - Simplified Component Styling
require 'fileutils'
require 'set'
module Joys
  module Styles
    def self.compile_component_styles(comp_name, base_css, media_queries, scoped)
      scope_prefix = scoped ? ".#{comp_name.tr('_', '-')} " : ""
      processed_base_css = base_css.map { |css| scope_css(css, scope_prefix) }
      processed_media_queries = {}
      
      # FIX: Actually iterate over the media_queries parameter
      media_queries.each do |key, css_rules|
        scoped_rules = css_rules.map { |css| scope_css(css, scope_prefix) }
        processed_media_queries[key] = scoped_rules
      end
      
      Joys.compiled_styles[comp_name] = {
        base_css: processed_base_css,
        media_queries: processed_media_queries,
        container_queries: {} # Keep this for compatibility, but media_queries contains all now
      }.freeze
    end
    
    private
    
    def self.render_consolidated_styles(used_components)
      return "" if used_components.empty?
      cache_key = used_components.to_a.sort.join(',')
      return Joys.consolidated_cache[cache_key] if Joys.consolidated_cache.key?(cache_key)
      buffer = String.new(capacity: 4096)
      min_queries = Hash.new { |h,k| h[k] = [] }
      max_queries = Hash.new { |h,k| h[k] = [] }
      minmax_queries = []
      container_min_queries = Hash.new { |h,k| h[k] = [] }
      container_max_queries = Hash.new { |h,k| h[k] = [] }
      container_minmax_queries = []
      container_named_queries = Hash.new { |h,k| h[k] = {min: Hash.new { |h,k| h[k] = [] }, max: Hash.new { |h,k| h[k] = [] }, minmax: []} }
      seen_base = Set.new
      
      used_components.each do |comp|
        styles = Joys.compiled_styles[comp] || next
        styles[:base_css].each do |rule|
          next if seen_base.include?(rule)
          buffer << rule
          seen_base << rule
        end
        styles[:media_queries].each do |key, rules|
          case key
          # FIX: Updated regex patterns to match the actual key formats
          when /^m-min-(\d+)$/
            min_queries[$1.to_i].concat(rules)
          when /^m-max-(\d+)$/
            max_queries[$1.to_i].concat(rules)
          when /^m-minmax-(\d+)-(\d+)$/
            minmax_queries << { min: $1.to_i, max: $2.to_i, css: rules }
          when /^c-min-(\d+)$/
            container_min_queries[$1.to_i].concat(rules)
          when /^c-max-(\d+)$/
            container_max_queries[$1.to_i].concat(rules)
          when /^c-minmax-(\d+)-(\d+)$/
            container_minmax_queries << { min: $1.to_i, max: $2.to_i, css: rules }
          when /^c-([^-]+)-min-(\d+)$/
            name, size = $1, $2.to_i
            container_named_queries[name][:min][size].concat(rules)
          when /^c-([^-]+)-max-(\d+)$/
            name, size = $1, $2.to_i
            container_named_queries[name][:max][size].concat(rules)
          when /^c-([^-]+)-minmax-(\d+)-(\d+)$/
            name, min_size, max_size = $1, $2.to_i, $3.to_i
            container_named_queries[name][:minmax] << { min: min_size, max: max_size, css: rules }
          end
        end
      end
      
      max_queries.sort.reverse.each do |bp, rules|
        buffer << "@media (max-width: #{bp}px){"
        rules.uniq.each { |r| buffer << r }
        buffer << "}"
      end
      min_queries.sort.each do |bp, rules|
        buffer << "@media (min-width: #{bp}px){"
        rules.uniq.each { |r| buffer << r }
        buffer << "}"
      end
      minmax_queries.sort_by { |q| [q[:min], q[:max]] }.each do |q|
        buffer << "@media (min-width: #{q[:min]}px) and (max-width: #{q[:max]}px){"
        q[:css].uniq.each { |r| buffer << r }
        buffer << "}"
      end
      container_max_queries.sort.reverse.each do |size, rules|
        buffer << "@container (max-width: #{size}px){"
        rules.uniq.each { |r| buffer << r }
        buffer << "}"
      end
      container_min_queries.sort.each do |size, rules|
        buffer << "@container (min-width: #{size}px){"
        rules.uniq.each { |r| buffer << r }
        buffer << "}"
      end
      container_minmax_queries.sort_by { |q| [q[:min], q[:max]] }.each do |q|
        buffer << "@container (min-width: #{q[:min]}px) and (max-width: #{q[:max]}px){"
        q[:css].uniq.each { |r| buffer << r }
        buffer << "}"
      end
      container_named_queries.each do |name, queries|
        queries[:max].sort.reverse.each do |size, rules|
          buffer << "@container #{name} (max-width: #{size}px){"
          rules.uniq.each { |r| buffer << r }
          buffer << "}"
        end
        queries[:min].sort.each do |size, rules|
          buffer << "@container #{name} (min-width: #{size}px){"
          rules.uniq.each { |r| buffer << r }
          buffer << "}"
        end
        queries[:minmax].sort_by { |q| [q[:min], q[:max]] }.each do |q|
          buffer << "@container #{name} (min-width: #{q[:min]}px) and (max-width: #{q[:max]}px){"
          q[:css].uniq.each { |r| buffer << r }
          buffer << "}"
        end
      end
      buffer.freeze.tap { |css| Joys.consolidated_cache[cache_key] = css }
    end
    
    def self.render_external_styles(used_components)
      return "" if used_components.empty?
      cache_key = used_components.to_a.sort.join(',')
      css_filename = "#{cache_key}.css"
      #css_filename = "#{Digest::SHA256.hexdigest(cache_key)[0..12]}.css"
      css_path = Joys.css_path || "public/css"
      full_path = File.join(css_path, css_filename)
      FileUtils.mkdir_p(css_path)
      unless File.exist?(full_path)
        css_content = render_consolidated_styles(used_components)
        File.write(full_path, css_content)
      end
      "<link rel=\"stylesheet\" href=\"/css/#{css_filename}\">"
    end
    
    def self.scope_css(css, scope_prefix)
      return css if scope_prefix.empty?
      selectors = css.split(',')
      scoped_selectors = selectors.map do |selector|
        selector.strip!
        if match = selector.match(/^\s*\.([a-zA-Z][\w-]*)/)
        #if selector.match(/^\s*\.([a-zA-Z][\w-]*)/)
          "#{scope_prefix}#{selector}"
        else
          selector
        end
      end
      scoped_selectors.join(', ')
    end
  end
end