# == RailsLogStat
require 'rubygems'
require 'ruby-debug'
class RailsLogStat
      
  class RequestStatsBuffer < Array

    # == RequestStatsBuffer::Stats
    class Stats
      attr_accessor :sql, :rendered
      attr_accessor :completion_time, :rendering_time, :db_time # completion stats
      attr_accessor :http_status, :url 

      def initialize
        @sql       = Hash.new{ |hash,key| hash[key] = [] }
        @rendered  = Hash.new{ |hash,key| hash[key] = [] }
        @completion_time, @rendering_time, @db_time = 0.0, 0.0, 0.0
        @http_status, @url = nil, nil
      end

      # stat_type => :sql or :rendered
      def add_stat stat_type, stat_name, timing
        stat = send stat_type
        stat[stat_name] << timing
      end

      # == sum
      # Returns the sum of all appearance of a given statistics
      def sum stat_type, stat_name
        send(stat_type)[stat_name].inject(0){ |sum, stat| sum += stat }
      end

      # == count
      # Returns number of appearances for a given stat
      def count stat_type, stat_name
        send(stat_type)[stat_name].size
      end
    end
    
    # === Instance methods
    def initialize request_name='', max_size=50
      @request_name, @max_size= request_name, max_size
      @stat_names = { :sql => {}, :rendered => {} }  # all unique names collected so far
      super() { Stats.new  }
    end
    
    def new_request
      shift until size < @max_size  # clear overflowed buffer
      push Stats.new         # the last stat is always the current stat
      self
    end
    
    
    # === SQL & Rendered Statistics
    # stat_type => :sql or :rendered
    def add_stat stat_type, stat_name, timing
      @stat_names[stat_type][stat_name] = true  # union of all stat names that has been added; needs to clear empty stat_names when buffer spills
      last.add_stat stat_type, stat_name, timing
    end
    
    def sum_of_stats stat_type, stat_name
      inject(0.0){|sum, stats| sum += stats.sum(stat_type, stat_name) }
    end
    
    def mean_of_stats stat_type, stat_name
      size == 0 ? 0.0 : sum_of_stats(stat_type, stat_name) / size 
    end
    
    def sum_of_counts stat_type, stat_name
      inject(0.0){|sum, stats| sum += stats.count(stat_type, stat_name) }
    end
    
    def mean_of_counts stat_type, stat_name
      size == 0 ? 0.0 : sum_of_counts(stat_type, stat_name) / size 
    end
    
    # === Completion Statistics
    def add_completion_stats completion_time, rendering_time, db_time, http_status, url
      last.completion_time, last.rendering_time, last.db_time, last.http_status, last.url = completion_time, rendering_time, db_time, http_status, url
    end
    
    def sum_of_completion_stats stat_name
      inject(0.0){|sum, stats| sum += stats.send(stat_name) }
    end
    
    def mean_of_completion_stats stat_name
      size == 0 ? 0.0 : sum_of_completion_stats(stat_name) / size
    end
    
    %w{completion_time rendering_time db_time}.each do |stat_name|
      define_method( "total_#{stat_name}"   ) { sum_of_completion_stats(stat_name)  }
      define_method( "average_#{stat_name}" ) { mean_of_completion_stats(stat_name) }
    end
    
    def to_stats_presenter stat_type
      stat_presenter = RequestStatsPresenter.new @request_name, size, average_completion_time, average_rendering_time, average_db_time
      @stat_names[stat_type].keys.each do |stat_name|
        stat_presenter[stat_name].average_count_per_request = mean_of_counts( stat_type, stat_name )
        stat_presenter[stat_name].average_time_per_request  = mean_of_stats( stat_type, stat_name )
      end
      stat_presenter
    end
    
    def to_completion_stats_presenter
      RequestStatsPresenter.new @request_name, size, average_completion_time, average_rendering_time, average_db_time
    end
    
    # Array of [ avg. count per request,   avg. time per request, model class name ]
    # notes average over the union might not be a good enough metrics, b/c some request might contain very little or no loads info for a specific model
    # it's generally a good idea to control your inputs for a specific log, so results are resonably consistent to compare with  
    def stats_collection stat_type
      to_stats_presenter(stat_type).to_a
    end
  end
  
  # presents one type of stats (sql or rendered)
  # plus general requests info
  class RequestStatsPresenter < Hash
    class Stats
      attr_accessor :average_count_per_request, :average_time_per_request, :high, :median, :low
      def initialize *arg
        @average_count_per_request, @average_time_per_request, @high, @median, @low = arg
      end      
    end
    
    attr_accessor :request_name, :request_count, :average_completion_time, :average_rendering_time, :average_db_time
    
    def initialize request_name='', request_count=0, average_completion_time=0.0, average_rendering_time=0.0, average_db_time=0.0
      @request_name, @request_count = request_name, request_count
      @average_completion_time, @average_rendering_time, @average_db_time = average_completion_time, average_rendering_time, average_db_time
      super() { |hash, key| hash[key] = Stats.new( *( [0.0] * 6) ) }
    end
    
    def request_name_with_average_completion_time count, spacing=50
      "---> #{request_name.ljust(spacing)}\t Avg. Completion Time: #{sprintf("%.5f",average_completion_time)} | Count: #{count}"
    end
    
    def to_a
      collect do |stat_name, stats|
        [stats.average_count_per_request, stats.average_time_per_request, stat_name]
      end
    end
  end
    
  # Processing IndexController#index (for 127.0.0.1 at 2008-04-13 06:40:20) [GET]
  # $1 => 'ActionController#index', $2 => 'GET'
  REQUEST_BEGIN_MATCHER = /Processing\s+(\S+Controller#\S+) \(for.+\) \[(GET|POST|PUT|DELETE)\]$/
  
  # ModelClassName Load (0.000292)SELECT * FROM `answers` WHERE `id` = 2000
  # $1 => ModelClassName, $2 => Load, $3 => 0.0453, $4 => SELECT
  SQL_MATCHER = /([A-Z]\S+)\s+(Load|Update|Create|Destroy).+\((\d+\.\d+)\).+(SELECT|UPDATE|INSERT|DELETE)/
  
  # Rendered layout/application (0.00995)
  # $1 => layout/application, $2 => 0.00995
  RENDERED_MATCHER = /^Rendered (\S+) \((\d+\.\d+)\)$/
  
  # Completed in 3.48602 (0 reqs/sec) | Rendering: 1.53868 (44%) | DB: 0.79623 (22%) | 200 OK [http://www.example.com]
  # $1 => 3.48602, $2 => 1.53868, $3 => 44, $4 => 0.79623, $5 => 22, $6 => 200 OK, $7 => http://www.example.com
  REQUEST_COMPLETION_FULL_MATCHER = /^Completed in (\d+\.\d+).+Rendering: (\d+\.\d+) \((\d+)%\).+DB: (\d+\.\d+) \((\d+)%\) \| ([1-5]\d{2} \S+) \[(.+)\]$/
  
  # Completed in 3.48602 (0 reqs/sec) | DB: 0.79623 (22%) | 200 OK [http://www.example.com]
  # $1 => 3.48602, $2 => 0.79623, $3 => 22, $4 => 200 OK, $5 => http://www.example.com
  REQUEST_COMPLETION_NO_RENDER_MATCHER = /^Completed in (\d+\.\d+).+DB: (\d+\.\d+) \((\d+)%\) \| ([1-5]\d{2} \S+) \[(.+)\]$/
    
  attr_accessor :log_file_path  # , :max_stats_per_request

  def initialize log_file_path, max_stats_per_request=50
    @log_file_path, @max_stats_per_request = log_file_path, max_stats_per_request
    @requests = Hash.new{ |hash,key| hash[key] = RequestStatsBuffer.new( key, @max_stats_per_request ) }
    @current_request = nil
  end
  
  def parse_log_file command="tail +0 -f"
    @log_thread ||= Thread.new do
      pipe = IO.popen "#{command.strip} #{log_file_path}", 'r'  # new pipe for tailing a text file
      while message_line = pipe.gets
        parse_line message_line
      end
    end
  end
  
  # Pattern match each line w/ Regexp
  def parse_line line
    if match = line.match( REQUEST_BEGIN_MATCHER )  
      request, method  = match[1], match[2]
      @current_request = "#{request} [#{method}]"   # => "ActionController#index [GET]"
      @current_request_stats_buffer = @requests[@current_request].new_request
    elsif match = line.match( SQL_MATCHER )
      if @current_request # guard against old queries that doesn't have leading request log
        operation, timing = match[2], match[3].to_f 
        model_name = "#{operation} #{match[1]}"
        @current_request_stats_buffer.add_stat( :sql, model_name, timing )
      end
    elsif match = line.match( RENDERED_MATCHER )
      rendered_file_name, timing = match[1], match[2].to_f
      @current_request_stats_buffer.add_stat( :rendered, rendered_file_name, timing )
    elsif match = line.match( REQUEST_COMPLETION_FULL_MATCHER )
      if @current_request
        @current_request_stats_buffer.add_completion_stats match[1].to_f, match[2].to_f, match[4].to_f, match[6], match[7]
      end
    elsif match = line.match( REQUEST_COMPLETION_NO_RENDER_MATCHER )
      if @current_request
        @current_request_stats_buffer.add_completion_stats match[1].to_f, 0.0, match[2].to_f, match[3], match[4]
      end
    end
  end
  
  # Array of [ avg. count per request,   avg. time per request, model class name ]
  # notes average over the union might not be a good enough metrics, b/c some request might contain very little or no loads info for a specific model
  # it's generally a good idea to control your inputs for a specific log, so results are resonably consistent to compare with  
  def averages_for_request request, stat_type
    @requests[request].stats_collection( stat_type ) 
  end
  
  def request_names_order_by_slowest
    if @requests.empty?
      []
    else
      max_spacing = @requests.keys.max{ |r1, r2| r1.size <=> r2.size }.size
      presenters = @requests.values.collect{|buffer| buffer.to_completion_stats_presenter }
      presenters.sort!{ |p1, p2| p1.average_completion_time <=> p2.average_completion_time }
      presenters.collect{ |p| p.request_name_with_average_completion_time(@requests[p.request_name].size, max_spacing) }
    end
  end
  
  def request_names
    @requests.keys
  end
  
  def request_count request
    @requests[request].size
  end
    
end

if __FILE__ == $0
  exit if PLATFORM =~ /win32/ || !STDOUT.tty?
  
  unless ARGV[0]
    puts 'You need to specify the path to the log file'
    exit
  end
  
  log_stat = RailsLogStat.new ARGV[0]
  log_stat.parse_log_file ARGV[1] || 'tail +0 -f'
      
  header_spacing = "\t"
  spacing = "\t"
  SQL_STATS_HEADERS = [ 'QUERIES / REQUEST', 'TOTAL TIME SPENT / REQUEST', 'MODEL NAME' ]
  SQL_STATS_HEADERS_OUTPUT = SQL_STATS_HEADERS.join( header_spacing )
  
  RENDERED_STATS_HEADERS = [ 'RENDERED / REQUEST', 'TOTAL TIME SPENT / REQUEST', 'TEMPLATE NAME' ]
  RENDERED_STATS_HEADERS_OUTPUT = RENDERED_STATS_HEADERS.join( header_spacing )

  SEPERATOR = '=' * 80
  DATA_SEPERATOR = '-' * 80
  
  # Command Loop
  loop do 
    puts "\nUsage: 'l' to list requests; type ('s' or 'r' '[request#name]') for sql & rendered stats..."
    case input = STDIN.gets.strip
    when 'l', 'ls', 'req', 'request', 'requests'
      log_stat.request_names_order_by_slowest.each { |request_line| puts request_line }
    when 'q', 'quit', 'exit'
      puts 'Bye!'
      exit      
    when /^(s|r)\S*\s+(\S+#.+\])$/   # s ApplictionController#index [GET], render ApplictionController#index [GET]
      request_name = $2
      puts request_name
      if log_stat.request_names.include? request_name
        if ($1 == 's') # s => sql
          stat_type = :sql 
          headers, headers_output = SQL_STATS_HEADERS, SQL_STATS_HEADERS_OUTPUT
        else # r => rendered
          stat_type = :rendered
          headers, headers_output = SQL_STATS_HEADERS, SQL_STATS_HEADERS_OUTPUT
        end
        
        output = [SEPERATOR, "#{request_name}: #{log_stat.request_count request_name} calls.", DATA_SEPERATOR, headers_output, DATA_SEPERATOR] 
        
        stats = log_stat.averages_for_request( request_name, stat_type )
        stats.sort!{ |stat1, stat2| stat1[1] <=> stat2[1] }
        stats.each do |stat|
          total_time_spent_per_request  = ("%.2f" % stat[0] )
          total_appearances_per_request = ( "%.6f" % stat[1] )
          output << [ total_time_spent_per_request.center(headers[0].size), total_appearances_per_request.center(headers[1].size), stat[2].to_s] * spacing
        end
        output << SEPERATOR
        puts output.join( "\n" )
      else
        puts 'ERROR: request not found...'
      end
    else
      puts 'ERROR: command not recongized'
    end
  end
end