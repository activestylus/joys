# Define a cycle helper that keeps its state per-key
# frozen_string_literal: true
# lib/joys/toys.rb - Intelligent Core Extensions
module Joys
  module Toys
    module CoreExtensions
      module Numeric
        
        # 3127613.filesize(:kb) => "3.0 GB", 1536.filesize => "1.5 KB"
        def filesize(unit = :bytes)
          # Convert input to bytes first
          bytes = case unit
                  when :bytes, :b then self
                  when :kb then self * 1024
                  when :mb then self * 1024 * 1024  
                  when :gb then self * 1024 * 1024 * 1024
                  when :tb then self * 1024 * 1024 * 1024 * 1024
                  else self
                  end
          
          # Then convert bytes to human readable
          return "#{bytes} B" if bytes < 1024
          
          units = [
            [1024**4, 'TB'],
            [1024**3, 'GB'], 
            [1024**2, 'MB'],
            [1024, 'KB']
          ]
          units.each do |threshold, suffix|
            if bytes >= threshold
              value = bytes.to_f / threshold
              formatted = value % 1 == 0 ? value.to_i.to_s : "%.1f" % value
              return "#{formatted} #{suffix}"
            end
          end
          
          "#{bytes} B"
        end
        # 21 => "21st", 102 => "102nd"
        def ordinal
          return self.to_s if self < 0
          
          suffix = case self.to_i % 100
                   when 11, 12, 13 then 'th'
                   else
                     case self.to_i % 10
                     when 1 then 'st'
                     when 2 then 'nd' 
                     when 3 then 'rd'
                     else 'th'
                     end
                   end
          "#{self}#{suffix}"
        end
        
        # 1200 => "1.2K", 1000000 => "1M", 1500000000 => "1.5B"
        def compact
          return self.to_s if self.abs < 1000
          
          units = [
            [1_000_000_000_000, 'T'],
            [1_000_000_000, 'B'], 
            [1_000_000, 'M'],
            [1_000, 'K']
          ]
          
          units.each do |threshold, suffix|
            if self.abs >= threshold
              value = self.to_f / threshold
              formatted = value % 1 == 0 ? value.to_i.to_s : "%.1f" % value
              return "#{formatted}#{suffix}"
            end
          end
          
          self.to_s
        end
        
        # 42 => "forty-two", 123 => "one hundred twenty-three"
        def spell
          return 'zero' if self == 0
          return self.to_s if self < 0 || self >= 1_000_000
          
          ones = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen]
          tens = %w[zero ten twenty thirty forty fifty sixty seventy eighty ninety]
          
          num = self.to_i
          result = []
          
          # Thousands
          if num >= 1000
            result << ones[num / 1000] + ' thousand'
            num %= 1000
          end
          
          # Hundreds
          if num >= 100
            result << ones[num / 100] + ' hundred'
            num %= 100
          end
          
          # Tens and ones
          if num >= 20
            ten_part = tens[num / 10]
            one_part = num % 10 > 0 ? ones[num % 10] : nil
            result << [ten_part, one_part].compact.join('-')
          elsif num > 0
            result << ones[num]
          end
          
          result.join(' ')
        end
        
        # 4 => "IV", 1994 => "MCMXCIV"
        def roman
          return '' if self <= 0 || self >= 4000
          
          values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
          numerals = %w[M CM D CD C XC L XL X IX V IV I]
          
          result = ''
          num = self.to_i
          
          values.each_with_index do |value, index|
            count = num / value
            result += numerals[index] * count
            num -= value * count
          end
          
          result
        end

        # 10.20.cash('€') => "10.20€", 10.20.cash('$') => "$10.20"  
        def cash(currency = '$')
          formatted = "%.2f" % self
          
          # Currency positioning logic
          case currency.to_s
          when '$', '¥', '₩', '₹', '₪' # Prefix currencies
            "#{currency}#{formatted}"
          when '€', '£', '₽', 'kr', 'zł' # Suffix currencies  
            "#{formatted}#{currency}"
          else # Unknown - default to prefix
            "#{currency}#{formatted}"
          end
        end
      end
      
      module String
        # "hello world-foo" => "Hello World Foo" (smart about separators)
        def title
          self.split(/[\s\-_]+/).map(&:capitalize).join(' ')
        end
        
        # "John Wesley Doe" => "JWD"
        def initials  
          self.split(/\s+/).map { |word| word[0]&.upcase }.compact.join
        end
        
        # "hello_world" => "HelloWorld"
        def camel
          self.split(/[\s\-_]+/).map.with_index { |word, i| 
            i == 0 ? word.downcase : word.capitalize 
          }.join
        end
        
        # "HelloWorld" => "hello_world"
        def snake
          self.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
        end
        
        # "Hello World!" => "hello-world"  
        def slug
          self.downcase
              .gsub(/[^\w\s\-]/, '') # Remove special chars except spaces/hyphens
              .strip
              .gsub(/[\s\-_]+/, '-') # Convert spaces/underscores to hyphens
              .gsub(/\-+/, '-')      # Collapse multiple hyphens
              .gsub(/^\-|\-$/, '')   # Remove leading/trailing hyphens
        end
        
        # "1234567890" => "(123) 456-7890"
        def phone
          digits = self.gsub(/\D/, '')
          return self if digits.length != 10
          
          "(#{digits[0..2]}) #{digits[3..5]}-#{digits[6..9]}"
        end
        
        # "Long text here".snip(10) => "Long te..." (smart ellipsis)
        def snip(length, ellipsis = '...')
          return self if self.length <= length
          return self if length < ellipsis.length + 1 # Don't make it longer!
          
          # Smart truncation - try to break on word boundary near the limit
          if length > 10
            word_break = self[0..length-ellipsis.length].rindex(/\s/)
            if word_break && word_break > length * 0.7 # Only if reasonably close
              return self[0..word_break-1] + ellipsis
            end
          end
          
          self[0..length-ellipsis.length-1] + ellipsis
        end
        
        # "hello world".hilite("world") => "hello <mark>world</mark>" 
        def hilite(term)
          return self if term.nil? || term.empty?
          self.gsub(/(#{Regexp.escape(term)})/i, '<mark>\1</mark>')
        end
        
        # "Secret info here".redact(/\w{6,}/) => "****** info ****"
        def redact(pattern = /\w{4,}/)
          self.gsub(pattern) { |match| '*' * match.length }
        end
      end
      
      module Time  
        # 2.hours.ago.ago => "2h ago" (smart recent time)
        def ago(format = :short)
          diff = ::Time.now - self
          return 'just now' if diff < 60
          
          case format
          when :short
            case diff
            when 0...3600        then "#{(diff/60).to_i}m ago"
            when 3600...86400    then "#{(diff/3600).to_i}h ago" 
            when 86400...2592000 then "#{(diff/86400).to_i}d ago"
            else strftime('%b %d')
            end
          when :long
            case diff  
            when 0...3600        then "#{(diff/60).to_i} minutes ago"
            when 3600...86400    then "#{(diff/3600).to_i} hours ago"
            when 86400...2592000 then "#{(diff/86400).to_i} days ago" 
            else strftime('%B %d, %Y')
            end
          end
        end
      end
      
      module Date
        # Date.today.weekday => "Mon", Date.today.weekday(:long) => "Monday"
        def weekday(format = :short)
          format == :long ? strftime('%A') : strftime('%a')
        end
        
        # Date.new(2024,6,15).season => "Summer"
        def season
          month = self.month
          case month
          when 12, 1, 2  then 'Winter'
          when 3, 4, 5   then 'Spring'  
          when 6, 7, 8   then 'Summer'
          when 9, 10, 11 then 'Fall'
          end
        end
        
        # Date.today.smart => "Today", Date.yesterday.smart => "Yesterday"
        def smart
          today = Date.today
          return 'Today' if self == today
          return 'Yesterday' if self == today - 1
          return 'Tomorrow' if self == today + 1
          
          # This year - show month/day
          if self.year == today.year
            strftime('%b %d')
          else
            strftime('%b %d, %Y')  
          end
        end
        
        # Date.today.schedule("+2d") => 2 days from now, Date.today.schedule("-1w") => 1 week ago
        def schedule(offset_string)
          match = offset_string.match(/([+-]?)(\d+)([dwmyh])/)
          return self unless match
          
          sign, amount, unit = match.captures
          multiplier = sign == '-' ? -1 : 1
          amount = amount.to_i * multiplier
          
          case unit
          when 'd' # days
            self + amount
          when 'w' # weeks  
            self + (amount * 7)
          when 'm' # months
            self >> amount # Use Ruby's month arithmetic
          when 'y' # years
            self >> (amount * 12)
          when 'h' # hours (convert to datetime)
            (self.to_time + (amount * 3600)).to_date
          else
            self
          end
        end
      end
      
      module Integer
        # 7265.duration => "2h 1m", 90.duration => "1m 30s"
        def duration(format = :short)
          seconds = self
          return '0s' if seconds == 0
          
          hours = seconds / 3600
          minutes = (seconds % 3600) / 60
          secs = seconds % 60
          
          parts = []
          parts << "#{hours}h" if hours > 0
          parts << "#{minutes}m" if minutes > 0  
          parts << "#{secs}s" if secs > 0 && hours == 0 # Only show seconds if under 1 hour
          
          parts.join(' ')
        end
      end
    end
  end
end

# Apply the extensions
Numeric.include Joys::Toys::CoreExtensions::Numeric  
String.include Joys::Toys::CoreExtensions::String
Time.include Joys::Toys::CoreExtensions::Time
Date.include Joys::Toys::CoreExtensions::Date  
Integer.include Joys::Toys::CoreExtensions::Integer
