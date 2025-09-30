# lib/joys/tags.rb
module Joys
  module Tags
    VOID_TAGS = %w[area base br col embed hr img input link meta param source track wbr].freeze
    TAGS = %w[
      a abbr address article aside audio b bdi bdo blockquote body button canvas
      caption cite code colgroup data datalist dd del details dfn dialog div dl dt
      em fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 head header hgroup
      html i iframe ins kbd label legend li main map mark menu meter nav noscript
      object ol optgroup option output p picture pre progress q rp rt ruby s samp
      script section select small span strong style sub summary sup table tbody td
      template textarea tfoot th thead time title tr u ul var video
    ].freeze
    BOOLEAN_ATTRS = %w[
      disabled readonly read_only multiple checked selected 
      auto_focus autofocus no_validate novalidate form_novalidate formnovalidate
      hidden required open reversed scoped seamless muted auto_play autoplay 
      controls loop default inert item_scope itemscope
    ].to_set.freeze
    
    CLS = ' class="'.freeze
    QUO = '"'.freeze
    BC = '>'.freeze
    BO = '<'.freeze
    GTS = '</'.freeze
    EQ = '="'.freeze
    
    VOID_TAGS.each do |tag|
      define_method(tag) do |cs: nil, **attrs|
        class_string = case cs
        when String, Symbol then cs.to_s
        when Array then cs.compact.reject { |c| c == false }.map(&:to_s).join(" ")
        else ""
        end
        
        @bf << BO << tag
        @bf << CLS << class_string << QUO unless class_string.empty?
        
        attrs.each do |k, v|
          key = k.to_s
          
          if v.is_a?(Hash) && (key == "data" || key.start_with?("aria"))
            prefix = key.tr('_', '-')
            v.each do |sk, sv|
              next if sv.nil? || sv == false  # Skip nil and boolean false
              attr_name = "#{prefix}-#{sk.to_s.tr('_', '-')}"
              @bf << " #{attr_name}#{EQ}#{CGI.escapeHTML(sv.to_s)}#{QUO}"
            end
          else
            next if v.nil?
            
            if BOOLEAN_ATTRS.include?(key)
              @bf << " #{key.tr('_', '')}" if v
            elsif v == false
              next
            else
              attr_name = key.tr('_', '-')
              @bf << " #{attr_name}#{EQ}#{CGI.escapeHTML(v.to_s)}#{QUO}"
            end
          end
        end
        
        @bf << BC
        nil
      end
    end
    
    TAGS.each do |tag|
      define_method(tag) do |content = nil, cs: nil, raw: false, **attrs, &block|
        class_string = case cs
        when String, Symbol then cs.to_s
        when Array then cs.compact.reject { |c| c == false }.map(&:to_s).join(" ")
        else ""
        end
        
        @bf << BO << tag
        @bf << CLS << class_string << QUO unless class_string.empty?
        
        attrs.each do |k, v|
          key = k.to_s
          
          if v.is_a?(Hash) && (key == "data" || key.start_with?("aria"))
            prefix = key.tr('_', '-')
            v.each do |sk, sv|
              next if sv.nil? || sv == false  # Skip nil and boolean false
              attr_name = "#{prefix}-#{sk.to_s.tr('_', '-')}"
              @bf << " #{attr_name}#{EQ}#{CGI.escapeHTML(sv.to_s)}#{QUO}"
            end
          else
            next if v.nil?
            
            if BOOLEAN_ATTRS.include?(key)
              @bf << " #{key.tr('_', '')}" if v
            elsif v == false
              next
            else
              attr_name = key.tr('_', '-')
              @bf << " #{attr_name}#{EQ}#{CGI.escapeHTML(v.to_s)}#{QUO}"
            end
          end
        end
        
        @bf << BC
        
        if block
          instance_eval(&block)
        elsif content
          @bf << (raw ? content.to_s : CGI.escapeHTML(content.to_s))
        end
        
        @bf << GTS << tag << BC
        nil
      end
      define_method("#{tag}!") do |content = nil, cs: nil, **attrs, &block|
        send(tag, content, cs: cs, raw: true, **attrs, &block)
      end
      define_method("#{tag}?") do |content = nil, cs: nil, **attrs, &block|
        parsed_content = Joys::Config.markup_parser.call(content.to_s)
        send(tag, parsed_content, cs: cs, raw: true, **attrs, &block)
      end
    end
  end
end