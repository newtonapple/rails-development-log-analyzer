$: << File.expand_path(File.dirname(__FILE__) + '/../lib')

# == Core Extensions
class Array
  def sum
    inject(0){ |sum, elem| sum += elem }
  end
  
  def avg
    sum / (size > 0 ? size : 1).to_f   
  end
end

# == Custom Matchers
module LogLineMatchers
  
  # subcalss must define @extraction_attribtues in Regexp matching order
  class LogLineMatcher
    def initialize *expected_extractions 
      @expected_extractions = expected_extractions
    end
    
    def matches? target
      match = target.match get_matcher
      unless match 
        @failure_message = "#{matcher_message_name} line: #{target} does not match regular expression."
        return false
      end
      
      @extraction_attribtues.each_with_index do |attribute, i|
        if match[i+1] != @expected_extractions[i]
          @failure_message = "#{matcher_message_name} line: #{target} does not contain #{attribute}: #{@expected_extractions[i]}."
          return false
        end
      end
    end
          
    def failure_message
      @failure_message
    end
    
    protected 
      # follow naming convention: class RequestBeginMatcher => REQUEST_BEGIN_MATCHER
      def get_matcher 
        @matcher_string = self.class.to_s.split('::').last.gsub(/([A-Z][a-z]+)/,'\1_').chomp('_').upcase
        @log_line_matcher = RailsLogStat.const_get( @matcher_string )
      end
      
      def matcher_message_name
        @matcher_message_name = @matcher_string.chomp('_MATCHER')
      end
  end
  
  class RequestBeginMatcher < LogLineMatcher
    def initialize controller_action, method
      @extraction_attribtues = ['Controller#action', 'HTTP_METHOD']
      super 
    end    
  end
      
  class SqlMatcher < LogLineMatcher
    def initialize model_class_name, ar_operation, time, sql_operation
      @extraction_attribtues = ['ModelClassName', 'ModelOperation', 'Time', 'SQLOperation']
      super
    end    
  end

  class RenderedMatcher < LogLineMatcher
    def initialize template, render_time
      @extraction_attribtues = ['Template', 'Time']
      super
    end    
  end
  class RequestCompletionMatcher < LogLineMatcher
    def initialize completion_time, render_time, render_percentage, db_time, db_percentage, http_status, url
      @extraction_attribtues = ['CompletionTime', 'RenderingTime', 'RenderingPercentage', 'DbTime', 'DbPercentage', 'HTTP_STATUS', 'URL']
      super
    end    
  end
  
  def extract_begin_request_properties expected
    RequestBeginMatcher.new expected[:controller_action], expected[:http_method]
  end
  
  def extract_sql_properties expected
    SqlMatcher.new expected[:model_name], expected[:ar_op], expected[:time], expected[:sql_op]
  end
    
  def extract_rendered_partial_properties expected
    RenderedMatcher.new expected[:template], expected[:render_time]
  end
  

  def extract_request_completion_properties expected
    RequestCompletionMatcher.new expected[:completion_time], expected[:render_time], expected[:render_percent], 
                                 expected[:db_time], expected[:db_percent], expected[:http_status], expected[:url]    
  end
  
end
