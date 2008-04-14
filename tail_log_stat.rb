require 'set'
class ARSqlLogStat
  

  # Processing IndexController#index (for 127.0.0.1 at 2008-04-13 06:40:20) [GET]
  BEGIN_REQUEST_MATCHER = /Processing\s+(\S+Controller#\S+) \(for.+\) \[(GET|POST)\]$/  # $1 => 'ActionController#index', $2 => 'GET'
  
  # ModelClassName Load (0.000292)SELECT * FROM `answers` WHERE `id` = 2000
  SQL_LOAD_MATCHER = /([A-Z]\S+)\s+Load.+\((\d+\.\d+)\).+SELECT/ # $1 => ModelNameM, $2 => 0.0453 
  
  attr_accessor :log_file_path, :max_stats_per_request

  def initialize log_file_path, max_stats_per_request=25
    # sample @request hash
    # { 
    #   'Article#index[POST]' => [
    #                              {'Article' => [0.2, 0.42332...], 'Body' => [0.45, 0.5923...] },  
    #                              {'Article' => [0.2, 0.435...], 'Body' => [0.33, 0.123...] },
    #                            ],
    # 
    #   'Article#index[GET]' => [
    #                              {'Article' => [0.2, 0.42332...], 'Body' => [0.45, 0.5923...] },  
    #                              {'Article' => [0.2, 0.435...], 'Body' => [0.33, 0.123...] },
    #                           ],
    #   ...
    # }
    @requests = new_hash_with_default
    @current_request = nil
    @log_file_path, @max_stats_per_request = log_file_path, max_stats_per_request
  end
  
  def parse_log_file command="tail -f"
    @log_thread ||= Thread.new do
      pipe = IO.popen "#{command.strip} #{log_file_path}", 'r'  # new pipe for tailing a text file
      while message_line = pipe.gets
        parse_line message_line
      end
    end
  end
  
  # Pattern matches message line
  def parse_line line
    if match = line.match( BEGIN_REQUEST_MATCHER )  
      request, method  = match[1], match[2]
      @current_request = "#{request} [#{method}]"   # => "ActionController#index [GET]"
      @current_request_stats = (@requests[@current_request] << new_hash_with_default).last # newest request stats is the one that just pushed into the buffer
      @requests[@current_request].unshift if @requests[@current_request].size == @max_stats_per_request  # pop out oldest request stats if buffer is full
    elsif match = line.match( SQL_LOAD_MATCHER )
      if @current_request # guard against old queries that doesn't have leading request log
        model_name, timing = match[1], match[2].to_f
        @current_request_stats[model_name] << timing
      end
    end
  end
  
  # [ model class name,    avg. # loads per request,   avg. time per request ]
  # notes average over the union might not be good enough a good enough metrics, b/c some request might contain very little or no loads for a specific model
  # it's generally a good idea to control your inputs for a specific log, so results can be resonably consistent to compare with
  def averges_for_request request
    unless (num_of_requests = @requests[request].size) == 0
      model_names = @requests[request].inject(Set.new){ |model_names, request_stats| model_names |= Set.new(request_stats.keys) }.to_a # union of all model names
      timing_sums = new_hash_with_default :float
      load_count_sums = new_hash_with_default :int 
      
      @requests[request].each do |request_stats|
        model_names.each do |model_name|
          timing_sums[model_name] += request_stats[model_name].inject(0.0){|sum, t| sum += t } # note, this can modify request_stats's keys since we have default hashes
          load_count_sums[model_name] += request_stats[model_name].size
        end
      end
      num_of_requests = num_of_requests.to_f
      model_names.collect do |model_name|
        [ load_count_sums[model_name] / num_of_requests, timing_sums[model_name] / num_of_requests, model_name ]
      end
    else
      []
    end
  end
  
  
  def request_names
    @requests.keys.sort
  end
  
  def request_count request
    @requests[request].size
  end
  
  private
    # simple factor for hash defaults
    def new_hash_with_default default_type=:array
      case default_type
      when :array
        Hash.new{ |hash,key| hash[key]=[] }
      when :int
        Hash.new{ |hash,key| hash[key]=0 }
      when :float
        Hash.new{ |hash,key| hash[key]=0.0 }
      end
    end
end


if __FILE__ == $0
  exit if PLATFORM =~ /win32/
  exit unless STDOUT.tty?
  unless ARGV[0]
    puts 'You need to specify the path to the log file'
    exit
  end
  
  log_stat = ARSqlLogStat.new ARGV[0]
  log_stat.parse_log_file ARGV[1] || 'tail -f'
  
  header_spacing = "\t"
  spacing = "\t" * 3
  headers = 'QUERIES / REQUEST' + header_spacing + 'TOTAL TIME SPENT / REQUEST' + header_spacing + 'MODEL NAME'
  
  loop do 
    puts "\n"
    puts "Usage: 'r' to list requests; type 'request name' for stats..."
    if (input = STDIN.gets.strip) == 'r'
      log_stat.request_names.each { |request_name| puts "--->  #{request_name}" }
    elsif input == 'q'
      puts 'Bye!'
      exit
    else
      if log_stat.request_names.include? input
        puts "#{'='*80}"
        puts "#{input}: #{log_stat.request_count input} calls."
        puts "#{'='*80}"
        puts headers
        puts '-' * 80
        stats = log_stat.averges_for_request(input)
        stats.sort!{ |stat1, stat2| stat2[1] <=> stat1[1] }
        stats.each do |stat|
          total_time_spent_per_request  = ('%.2f' % stat[0] )
          total_loads_per_request  = ('%.6f' % stat[1] )
          puts total_time_spent_per_request + spacing + total_loads_per_request + spacing + stat[2].to_s
        end
        puts "#{'='*80}"
      else
        puts 'ERROR: request not found...'
      end
    end
  end
end