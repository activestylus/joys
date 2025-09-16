# frozen_string_literal: true
# lib/joys/helpers.rb
module Joys
  module Render
    module Helpers
      def txt(content); @bf << CGI.escapeHTML(content.to_s); nil; end
      def raw(content); @bf << content.to_s; nil; end
      def push(name, &block)
        old_buffer = @bf;@slots ||= {}
        @bf = String.new;instance_eval(&block)
        content = @bf;@slots[name] = content
        @bf = old_buffer;nil
      end
      def pull(name = :main)
        @slots ||= {};@bf << @slots[name].to_s if @slots[name];nil
      end
      def pull_styles;@bf << "<!--STYLES-->";nil;end
      def pull_external_styles;@bf << "<!--EXTERNAL_STYLES-->";nil;end

def comp(name, *args, **kwargs, &block)
  comp_name = "comp_#{name}"
  @used_components ||= Set.new
  @used_components.add(comp_name)
  raw Joys.send(comp_name, *args, **kwargs, &block)
end
      def layout(name, &block)
        layout_lambda = Joys.layouts[name]
        raise ArgumentError, "Layout `#{name}` not registered" unless layout_lambda
        raw layout_lambda.call(self, &block)
      end
      def styles(scoped: false, &block)
        context_name = Joys.current_component
        context_name ||= Joys.current_page
        context_name ||= @current_page
        return nil unless context_name
        return nil if Joys.compiled_styles[context_name]
        @style_base_css = []
        @style_media_queries = {}
        @style_scoped = scoped
        instance_eval(&block)
        Joys::Styles.compile_component_styles(
          context_name,
          @style_base_css,
          @style_media_queries,
          @style_scoped
        )
        if context_name&.start_with?('page_')
          @used_components ||= Set.new
          @used_components.add(context_name)
        end
        @style_base_css = @style_media_queries = @style_scoped = nil;nil
      end
      def doctype;raw  "<!doctype html>";end
      def css(content);@style_base_css&.push(content);nil;end
      def media_max(breakpoint, content)
        return nil unless @style_media_queries
        key = "m-max-#{breakpoint}"
        @style_media_queries[key] ||= []
        @style_media_queries[key] << content;nil
      end
      def media_min(breakpoint, content)
        return nil unless @style_media_queries  
        key = "m-min-#{breakpoint}"
        @style_media_queries[key] ||= []
        @style_media_queries[key] << content;nil
      end
      def media_minmax(min_bp, max_bp, content)
        return nil unless @style_media_queries
        key = "m-minmax-#{min_bp}-#{max_bp}"
        @style_media_queries[key] ||= []
        @style_media_queries[key] << content;nil
      end
      def container_min(size, content)
        return nil unless @style_media_queries
        key = "c-min-#{size}"
        @style_media_queries[key] ||= []
        @style_media_queries[key] << content;nil
      end
      def container_max(size, content)
        return nil unless @style_media_queries
        key = "c-max-#{size}"
        @style_media_queries[key] ||= []
        @style_media_queries[key] << content;nil
      end
      def container_minmax(min_size, max_size, content)
        return nil unless @style_media_queries
        key = "c-minmax-#{min_size}-#{max_size}"
        @style_media_queries[key] ||= []
        @style_media_queries[key] << content;nil
      end
      def named_container_min(name, size, content)
        return nil unless @style_media_queries
        key = "c-#{name}-min-#{size}"
        @style_media_queries[key] ||= []
        @style_media_queries[key] << content;nil
      end
      def named_container_max(name, size, content)
        return nil unless @style_media_queries
        key = "c-#{name}-max-#{size}"
        @style_media_queries[key] ||= []
        @style_media_queries[key] << content;nil
      end
      def named_container_minmax(name, min_size, max_size, content)
        return nil unless @style_media_queries
        key = "c-#{name}-minmax-#{min_size}-#{max_size}"
        @style_media_queries[key] ||= []
        @style_media_queries[key] << content;nil
      end
    end
  end
end