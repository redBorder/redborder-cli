require 'pp'
class LogstashCmd < CmdParse::Command
  def initialize
    super('logstash')
    short_desc('Logstash actions and values')
    add_command(LogstashStatusCmd.new, default: true)
    add_command(LogstashPipelinesCmd.new, default: false)
    add_command(LogstashPipelineCmd.new, default: false)
    add_command(LogstashPluginsCmd.new, default: false)
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
        puts "Reloads"
        puts "\tSuccesses: " + response["successes"].to_s
        puts "\tFailures: " + response["failures"].to_s
        unless response["last_success_date"] == nil
          puts "\tLast success date: " + response["last_success_date"]
        end
        unless response["last_error"] == nil
          puts "\tError: " + response["last_error"]["message"]
        end
        unless response["last_failure_timestamp"] == nil
          puts "\tLast failure date: " + response["last_failure_timestamp"] + "\n"
        end
      end
      puts "\n"
    end
  end
end
#
# get_logstash_plugins
class LogstashPluginsCmd < CmdParse::Command
  def initialize
    super('plugins', takes_commands: false)
    short_desc('Show Logstash plugin list')
  end

  def execute()
    utils = Utils.instance
    logstash = utils.get_logstash_plugins
    puts "Logstash Plugins:\n\n"
    puts "Total: " + logstash["total"].to_s

    if logstash["plugins"]
      logstash["plugins"].each do |plugin|
        margin = (plugin["name"].size < 24 ) ? "\t\t" : "\t"
        puts plugin["name"] + margin + plugin["version"]
      end
    end
    puts "\n"
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
    unless logstash == nil
      puts "Logstash Status:\n\n"
      puts "Host: " + logstash["host"]
      puts "version: " + logstash["version"]
      puts "Address: " + logstash["http_address"]
      puts "ID: " + logstash["id"]
      puts "Name: " + logstash["name"]
      puts "Ephemeral ID: " + logstash["ephemeral_id"]
      puts "Status: " + logstash["status"]
      puts "Snapshot " + logstash["snapshot"].to_s
      puts "\nPipeline: "
      puts "\tWorkers:  " + logstash["pipeline"]["workers"].to_s
      puts "\tBatch size:  " + logstash["pipeline"]["batch_size"].to_s
      puts "\tBatch delay:  " + logstash["pipeline"]["batch_delay"].to_s
      puts "\nProcess: "
      puts "\tOpen file descriptors:  " + logstash["process"]["open_file_descriptors"].to_s
      puts "\tPeak open file descriptors:  " + logstash["process"]["peak_open_file_descriptors"].to_s
      puts "\tMax file descriptors:  " + logstash["process"]["max_file_descriptors"].to_s
      puts "\tMemory (total virtual in bytes): " + logstash["process"]["mem"]["total_virtual_in_bytes"].to_s
      puts "\tCPU:"
      puts "\t\tTotal in millis: " + logstash["process"]["cpu"]["total_in_millis"].to_s
      puts "\t\tPercent: " + logstash["process"]["cpu"]["percent"].to_s
      puts "\t\tLoad Average: " + "1m = " + logstash["process"]["cpu"]["load_average"]["1m"].to_s + "  5m = " + logstash["process"]["cpu"]["load_average"]["5m"].to_s + "  15m = " + logstash["process"]["cpu"]["load_average"]["15m"].to_s
      puts
    end
  end
end

$parser.add_command(LogstashCmd.new)