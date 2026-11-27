class VortexCmd < CmdParse::Command
  def initialize
    super('vortex')
    short_desc('redborder-vortex actions and values')
    add_command(VortexStatusCmd.new, default: true)
    add_command(VortexPipelinesCmd.new, default: false)
    add_command(VortexPipelineCmd.new, default: false)
  end
end

class VortexStatusCmd < CmdParse::Command
  def initialize
    super('status', takes_commands: false)
    short_desc('Show status of redborder-vortex service')
  end

  def execute
    vortex = Utils.instance.get_vortex_stats
    return puts 'redborder-vortex is not running or its IPC socket is not available' if vortex.empty?

    puts "redborder-vortex Status:\n\n"
    puts 'Node: ' + vortex['node_name'].to_s
    puts 'Uptime (seconds): ' + vortex['uptime_seconds'].to_s
    puts 'rbwindow leader: ' + vortex['is_rbwindow_leader'].to_s
    puts 'Workers: ' + vortex['active_workers'].to_s + '/' + vortex['total_workers'].to_s
    puts "\nEvents:"
    puts "\tReceived: " + vortex['events_received'].to_s
    puts "\tEmitted: " + vortex['events_emitted'].to_s
    puts "\tDropped: " + vortex['events_dropped'].to_s
    puts "\tFailed: " + vortex['events_failed'].to_s
    puts "\nCluster nodes: " + Array(vortex['cluster_nodes']).join(', ')
    puts
  end
end

class VortexPipelinesCmd < CmdParse::Command
  def initialize
    super('pipelines', takes_commands: false)
    short_desc('Pipelines from redborder-vortex')
  end

  def execute
    vortex = Utils.instance.get_vortex_stats
    puts "redborder-vortex Pipelines:\n\n"
    Array(vortex['pipelines']).each do |pipeline|
      line = pipeline['id'].to_s
      line += "\tErrors: " + pipeline['errors'].to_s if pipeline['errors'].to_i > 0
      puts line
    end
    puts "\n"
  end
end

class VortexPipelineCmd < CmdParse::Command
  def initialize
    super('pipeline', takes_commands: false)
    short_desc('Show a redborder-vortex pipeline')
  end

  def execute(pipeline_name)
    vortex = Utils.instance.get_vortex_stats
    pipeline = Array(vortex['pipelines']).find { |p| p['id'] == pipeline_name }
    return puts "Pipeline #{pipeline_name} not found" if pipeline.nil?

    puts pipeline['id']
    puts 'Workers: ' + pipeline['workers'].to_s
    puts 'Input topics: ' + Array(pipeline['input_topics']).join(', ')
    puts 'Consumer group: ' + pipeline['consumer_group'].to_s
    puts "\nEvents:"
    puts "\tIn: " + pipeline['events_in'].to_s
    puts "\tOut: " + pipeline['events_out'].to_s
    puts "\tDropped: " + pipeline['events_dropped'].to_s
    puts "\tErrors: " + pipeline['errors'].to_s
    puts "\tLast run duration (us): " + pipeline['last_run_duration_us'].to_s
    puts "\n"
  end
end

$parser.add_command(VortexCmd.new)
