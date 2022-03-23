require 'pp'
class LogstashCmd < CmdParse::Command
  def initialize
    super('logstash')
    short_desc('Logstash actions and values')
    add_command(LogstashStatusCmd.new, default: false)
    add_command(LogstashPipelinesCmd.new, default: true)
    add_command(LogstashPipelineCmd.new, default: false)
  end
end

#    options.on('-p', '--pipeline', 'Pipeline') { $parser.data[:pipeline] = true }
class LogstashPipelinesCmd < CmdParse::Command
  def initialize
    super('pipelines', takes_commands: false)
    short_desc('Pipelines from Logstash')
  end

  def execute()
    utils = Utils.instance
    logstash = utils.get_logstash_pipelines
    puts "Logstash Pipelines:\n\n"
    if logstash["pipelines"]
      logstash["pipelines"].each do |name, pipeline|
        # name, value = pipeline.first
        puts name
        # puts pipeline["name"]
        response =  pipeline["reloads"]
        unless response["failures"] == 0
          if response["last_error"]
            puts "\tError: " + response["last_error"]["message"]
            puts "\tLast failure date: " + response["last_failure_timestamp"] + "\n"
          end
        end
      end
    end
    puts "\n"
  end
end

class LogstashPipelineCmd < CmdParse::Command
  def initialize
    $parser.data[:pipeline] = false
    super('pipeline', takes_commands: false)
    short_desc('Show a logstash pipeline')
    options.on('-p', '--pipeline', 'Pipeline') { $parser.data[:pipeline] = true }
  end

  def execute(pipeline_name)
    utils = Utils.instance
    logstash = utils.get_logstash_pipeline(pipeline_name)
    if logstash["pipelines"]
      logstash["pipelines"].each do |name, pipeline|
        puts name
        puts "\nEvents:"
        puts "\tFiltered: " + pipeline["events"]["filtered"].to_s
        puts "\tOut: " + pipeline["events"]["out"].to_s
        puts "\tDurantion (millis): " + pipeline["events"]["duration_in_millis"].to_s
        puts "\nPlugins:"
        pipeline["plugins"].each do |plugin_type, plugin_list|
          puts "\t#{plugin_type}"
          list_filtered = []
          plugin_list.each do |plugin|
            list_filtered.push(plugin["name"])
          end
          list_filtered = list_filtered.uniq
          list_filtered.each do |plugin|
            puts "\t\t#{plugin}"
          end
        end
        response =  pipeline["reloads"]
        unless response["failures"] == 0
          if response["last_error"]
            puts "\n\tError: " + response["last_error"]["message"]
            puts "\tLast failure date: " + response["last_failure_timestamp"] + "\n"
          end
        end
      end
    end
  end
end

class LogstashStatusCmd < CmdParse::Command
  def initialize
    super('status', takes_commands: false)
    short_desc('Show status of Logstash service')
  end

  def execute()
    utils = Utils.instance
    logstash = utils.get_logstash_status
    puts "Logstash Status:\n\n"
    jj logstash
    puts "\n"
  end
end

$parser.add_command(LogstashCmd.new)