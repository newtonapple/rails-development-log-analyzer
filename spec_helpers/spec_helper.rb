$: << File.expand_path(File.dirname(__FILE__) + '/../lib')

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


  # Rendered layout/application (0.00995)
  # $1 => layout/application, $2 => 0.00995
  # RENDERED_MATCHER = /^Rendered (\S+) \((\d+\.\d+)\)$/

  class RenderedMatcher < LogLineMatcher
    def initialize template, render_time
      @extraction_attribtues = ['Template', 'Time']
      super
    end    
  end
  
  def extract_model_name_and_ar_op_and_time_and_sql_op model_class_name, ar_operation, time, sql_operation
    SqlMatcher.new model_class_name, ar_operation, time, sql_operation
  end
  
  def extract_controller_action_and_http_method controller_action, method
    RequestBeginMatcher.new controller_action, method
  end
  
  def extract_template_and_render_time template, render_time
    RenderedMatcher.new template, render_time
  end
  
end
