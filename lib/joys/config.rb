# frozen_string_literal: true
module Joys
  def self.html(&block)
    renderer = Object.new
    renderer.extend(Render::Helpers)
    renderer.extend(Tags)
    renderer.instance_variable_set(:@bf, String.new)
    renderer.instance_variable_set(:@current_page, "page_standalone")
    renderer.instance_variable_set(:@used_components, Set.new)
    renderer.instance_variable_set(:@slots, {})
    renderer.instance_eval(&block)
    renderer.instance_variable_get(:@bf)
  end
  module Config
    class << self
      attr_accessor :env,:pages,:layouts,:components,:css_parts,:helpers,:markup_parser
      def markup_parser
        @markup_parser ||= ->(content) { content.to_s }
      end
      def env;@env||=ENV['JOYS_ENV']||(defined?(::Rails) ? ::Rails.env.to_s : "development");end
      def dev?;env!="production";end
      def pages;@pages||=path("pages");end
      def layouts;@layouts||=path("layouts");end  
      def components;@components||=path("components");end
      def css_parts;@css_parts||=path("css");end
      def helpers;@helpers||=path("helpers");end
      private
      def path(t);defined?(::Rails) ? ::Rails.root.join("app/views/joys/#{t}").to_s : "views/joys/#{t}";end
    end
  end
  module Adapters
    class Base
      def integrate!;raise NotImplementedError;end
      def inject_helpers!;raise NotImplementedError;end
      def controller_context(controller);{};end
    end
    class Rails < Base
      def integrate!
        return unless defined?(ActionController::Base)
        ActionController::Base.include(ControllerMethods)
        inject_helpers!
        ::Rails.application.config.to_prepare do
          Joys.preload! if ::Rails.env.production?
          Joys::Render::Helpers.include(::Rails.application.helpers)
        end
      end
      def inject_helpers!
        Joys::Render::Helpers.include(ActionView::Helpers)
        Joys::Render::Helpers.module_eval do
          def request;Thread.current[:joys_request];end
          def params;Thread.current[:joys_params];end
          def current_user;Thread.current[:joys_current_user];end
          def session;Thread.current[:joys_session];end
          def _(content);raw(content);end
        end
      end
      def controller_context(controller)
        {
          joys_request: controller.request,
          joys_params: controller.params,
          joys_current_user: (controller.current_user if controller.respond_to?(:current_user)),
          joys_session: controller.session
        }
      end
      module ControllerMethods
        def render_joy(path, **locals)
          Joys.reload! if Config.dev?
          file = File.join(Config.pages, "#{path}.rb")
          raise "Template not found: #{file}" unless File.exist?(file)
          
          renderer = Object.new
          renderer.extend(Render::Helpers)
          locals.each { |k, v| renderer.instance_variable_set(:"@#{k}", v) }
          
          result = renderer.instance_eval(File.read(file), file)
          result.is_a?(String) ? result.freeze : ""
        end
      end
    end
    class Sinatra < Base
      def integrate!;end
      def inject_helpers!;end
    end
    class Hanami < Base  
      def integrate!;end
      def inject_helpers!;end
    end
    class Roda < Base
      def integrate!;end  
      def inject_helpers!;end
    end
  end
  class << self
    attr_accessor :adapter,:css_registry
    def render_joy(path,**locals)
      Joys.reload! if Config.dev?
      file=File.join(Config.pages,"#{path}.rb")
      raise "Template not found: #{file}" unless File.exist?(file)
      locals.each{|k,v|eval("@#{k}=v",binding)}
      result=eval(File.read(file),binding,file)
      result.is_a?(String) ? result.freeze : ""
    end
    def preload!;load_helpers;load_dir(Config.layouts);load_dir(Config.components);load_css_parts;end
    def load_helpers
      return unless Dir.exist?(Config.helpers)
      Dir.glob("#{Config.helpers}/**/*.rb").each do |f|
        helper_module = Module.new
        helper_module.module_eval(File.read(f), f)
        Joys::Render::Helpers.include(helper_module)
      end
    end
    def load_css_parts
      return unless Dir.exist?(Config.css_parts)
      Dir.glob("#{Config.css_parts}/**/*.css").each do |f|
        relative_path = f.sub("#{Config.css_parts}/", '').sub('.css', '')
        @css_registry[relative_path] = File.read(f).gsub(/\r\n?|\n/, '')
      end
    end
    def detect_framework!
      @css_registry={}
      @adapter=if defined?(ActionController::Base)&&defined?(::Rails)
        Adapters::Rails.new
      elsif defined?(Sinatra::Base)
        Adapters::Sinatra.new  
      elsif defined?(Hanami::Action)
        Adapters::Hanami.new
      elsif defined?(Roda)
        Adapters::Roda.new
      end
      @adapter&.integrate!
    end
    def reload!;clear_cache!;@css_registry={};preload!;end
    def load_dir(dir);Dir.exist?(dir)&&Dir.glob("#{dir}/**/*.rb").each{|f|load f};end
  end
end
Joys.detect_framework!