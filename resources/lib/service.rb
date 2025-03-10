require 'chef'

class ServiceCmd < CmdParse::Command
  def initialize
    super('service')
    short_desc('Manage service actions and values')
    add_command(ServiceListCmd.new, default: true)
    add_command(ServiceEnableCmd.new, default: false)
    add_command(ServiceDisableCmd.new, default: false)
    add_command(ServiceStartCmd.new, default: false)
    add_command(ServiceStopCmd.new, default: false)
  end
end

class ServiceListCmd < CmdParse::Command
  RESET = "\033[0m"
  RED = "\033[31m"
  GREEN = "\033[32m"
  BLUE = "\033[34m"
  YELLOW = "\033[33m"
  BLINK = "\033[5m"

  def initialize
    $parser.data[:show_runtime] = true
    $parser.data[:no_color] = false
    super('list', takes_commands: false)
    short_desc('List services from node')
    options.on('-q', '--quiet', 'Show list without runtime') { $parser.data[:show_runtime] = false }
    options.on('-n', '--no-color', 'Print without colors') { $parser.data[:no_color] = true }
  end

  def execute()
    utils = Utils.instance
    node_name = Socket.gethostname.split(".").first

    # Set colors
    if $parser.data[:no_color]
      red, green, yellow, blue, reset, blink = ''
    else
      red, green, yellow, blue, reset, blink = RED, GREEN, YELLOW, BLUE, RESET, BLINK
    end

    unless File.exist?('/etc/redborder/services.json')
      puts 'ERROR: Services list not found'
      return
    end

    services = JSON.parse(File.read('/etc/redborder/services.json'))
    external_services = JSON.parse(File.read('/var/chef/data/data_bag/rBglobal/external_services.json')) rescue {}

    # Counters
    running = 0
    stopped = 0
    external = 0
    errors = 0

    # Paint service list
    if $parser.data[:show_runtime]
      printf("================================= Services ==================================\n")
      printf("%-33s %-33s %-10s\n", "Service", "Status(#{node_name})", "Runtime")
      printf("-----------------------------------------------------------------------------\n")
    else
      printf("=========================== Services ============================\n")
      printf("%-33s %-10s\n", "Service", "Status(#{node_name})")
      printf("-----------------------------------------------------------------\n")
    end

    services.uniq.sort.each do |systemd_service, enabled|
      if system("systemctl status #{systemd_service} &>/dev/null")
        ret = "running"
        running = running + 1

        if $parser.data[:show_runtime]
          runtime = `systemctl status #{systemd_service} | grep 'Active:' | awk '{for(i=9;i<=NF;i++) printf $i " "; print ""}'`.strip

          # Blink when runtime is less than a minute
          if runtime.match?(/^\d+\s*s/)
            printf("%-33s #{green}%-33s#{reset}#{blink}%-10s#{reset}\n", "#{systemd_service}:", ret, runtime)
          else
            printf("%-33s #{green}%-33s#{reset}%-10s\n", "#{systemd_service}:", ret, runtime)
          end
        else
          printf("%-33s #{green}%-10s#{reset}\n", "#{systemd_service}:", ret)
        end
      elsif !enabled
        ret = "not running"
        stopped = stopped + 1
        runtime = "N/A"
        if $parser.data[:show_runtime]
          printf("%-33s #{yellow}%-33s#{reset}%-10s\n", "#{systemd_service}:", ret, runtime)
        else
          printf("%-33s #{yellow}%-10s#{reset}\n", "#{systemd_service}:", ret)
        end
      elsif (external_services.include?(systemd_service) && external_services[systemd_service] == "external") ||
        (systemd_service == 'minio' && external_services.include?('s3') && external_services['s3'] == 'external')
        ret = "external"
        external = external + 1
        runtime = "N/A"
        if $parser.data[:show_runtime]
          printf("%-33s #{blue}%-33s#{reset}%-10s\n", "#{systemd_service}:", ret, runtime)
        else
          printf("%-33s #{blue}%-10s#{reset}\n", "#{systemd_service}:", ret)
        end
      else
        ret = "not running!!"
        errors = errors + 1
        runtime = "N/A"
        if $parser.data[:show_runtime]
          printf("%-33s #{red}%-33s#{reset}%-10s\n", "#{systemd_service}:", ret, runtime)
        else
          printf("%-33s #{red}%-10s#{reset}\n", "#{systemd_service}:", ret)
        end
      end
    end

    if $parser.data[:show_runtime]
      printf("-----------------------------------------------------------------------------\n")
    else
      printf("-----------------------------------------------------------------\n")
    end
    printf("%-33s %-10s\n","Total:", services.count)
    if $parser.data[:show_runtime]
      printf("-----------------------------------------------------------------------------\n")
    else
      printf("-----------------------------------------------------------------\n")
    end
    printf("Running: #{running}  /  Stopped: #{stopped}  /  External: #{external}  /  Errors: #{errors}\n\n")
  end
end

class ServiceEnableCmd < CmdParse::Command
  def initialize
    $parser.data[:all_services] = false
    super('enable', takes_commands: false)
    short_desc('Enable service from node')
  end

  def execute(node=nil, service)
    nodes = []
    utils = Utils.instance
    saved = false

    begin
      nodes = utils.check_nodes(node || Socket.gethostname.split(".").first)
      if nodes.count == 0
        services.insert(0, node)
        nodes << Socket.gethostname.split(".").first
      end
    rescue Errno::ECONNREFUSED # If the node is ips/proxy, is not reachable
      if node == Socket.gethostname.split(".").first
        nodes << node
      else
        services = node
        nodes << Socket.gethostname.split(".").first
      end
    end

    nodes.each do |n|
      node = utils.get_node(n)
      unless node
        puts "ERROR: Node not found!"
        next
      end
      services = node.attributes['redborder']['services'] || []
      systemd_services = node.attributes['redborder']['systemdservices']
      if node.role?('manager')
        group_of_the_service = systemd_services[service]
        services_with_same_group = systemd_services.select{|service,group| group == group_of_the_service }.keys || []

        role = Chef::Role.load(n)
        role.override_attributes["redborder"]["services"] = {} if !role.override_attributes["redborder"].include? "services" # Initialize services in case do not exists

        # save info at the node too
        node.override!["redborder"]["services"] = {} if node["redborder"]["services"].nil?
        node.override!["redborder"]["services"]["overwrite"] = {} if node["redborder"]["services"]["overwrite"].nil?

        services_with_same_group.each do |s|
          role.override_attributes["redborder"]["services"][s] = true
          node.override!["redborder"]["services"]["overwrite"][s] = true
          puts "#{s} enabled on #{n}"
        end
        puts "ERROR: Service not found" if services_with_same_group.nil? || services_with_same_group.empty?
        role.save
      else
        enabled_services = {}
        systemd_services.each do |service_name, systemd_name|
          enabled_services[systemd_name.first] = services[service_name]
        end
        enabled_services[service] = true if enabled_services.include?(service)

        systemd_services.each do |service_name, systemd_name|
          if systemd_name.join(',') == service
            node.override['redborder']['services'][service_name] = true
            saved = true
          end
        end
        if saved
          puts "#{service} enabled on #{node.name}"
          puts 'Saving services enablement into /etc/redborder/services.json'
          File.write('/etc/redborder/services.json', JSON.pretty_generate(enabled_services))
          node.save
        else
          puts "ERROR: Service not found"
        end
      end
    end
  end
end

class ServiceDisableCmd < CmdParse::Command
  def initialize
    $parser.data[:all_services] = false
    super('disable', takes_commands: false)
    short_desc('Disable service from node')
  end

  def execute(node=nil, service)
    nodes = []
    utils = Utils.instance
    saved = false

    begin
      nodes = utils.check_nodes(node || Socket.gethostname.split(".").first)
      if nodes.count == 0
        services.insert(0, node)
        nodes << Socket.gethostname.split(".").first
      end
    rescue Errno::ECONNREFUSED # If the node is ips/proxy, is not reachable
      if node == Socket.gethostname.split(".").first
        nodes << node
      else
        services = node
        nodes << Socket.gethostname.split(".").first
      end
    end

    if service == 's3'
      total_enabled_nodes = 0
      utils.check_nodes("all").each do |n|
        n_node = utils.get_node(n)
        next unless n_node
        role = Chef::Role.load(n)
        if role.override_attributes.dig('redborder','services','s3').nil?
          s3_role = n_node['redborder']['services']['s3']
        else
          s3_role = role.override_attributes["redborder"]["services"]["s3"]
        end
        total_enabled_nodes += 1 if s3_role
      end

      if total_enabled_nodes <= 1
        puts "ERROR: Service 's3' is enabled on only one node. Cannot disable it."
        return
      end
    end

    nodes.each do |n|
      node = utils.get_node(n)
      unless node
        puts "ERROR: Node not found!"
        next
      end
      services = node.attributes['redborder']['services'] || []
      systemd_services = node.attributes['redborder']['systemdservices'] || []
      if node.role?('manager')
        group_of_the_service = systemd_services[service]
        services_with_same_group = systemd_services.select { |s, group| group == group_of_the_service }.keys || []

        role = Chef::Role.load(n)
        role.override_attributes["redborder"]["services"] = {} unless role.override_attributes["redborder"].include?("services")

        # Save info at the node too
        node.override!["redborder"]["services"] = {} if node["redborder"]["services"].nil?
        node.override!["redborder"]["services"]["overwrite"] = {} if node["redborder"]["services"]["overwrite"].nil?

        services_with_same_group.each do |s|
          role.override_attributes["redborder"]["services"][s] = false
          node.override!["redborder"]["services"]["overwrite"][s] = false
          puts "#{s} disabled on #{n}"
        end
        puts "ERROR: Service not found" if services_with_same_group.nil? || services_with_same_group.empty?
        role.save
      else
        enabled_services = {}
        systemd_services.each do |service_name, systemd_name|
          enabled_services[systemd_name.first] = services[service_name]
        end
        enabled_services[service] = false if enabled_services.include?(service)

        systemd_services.each do |service_name, systemd_name|
          if systemd_name.join(',') == service
            node.override['redborder']['services'][service_name] = false
            saved = true
          end
        end
        if saved
          puts "#{service} disabled on #{node.name}"
          puts 'Saving services disablement into /etc/redborder/services.json'
          File.write('/etc/redborder/services.json', JSON.pretty_generate(enabled_services))
          node.save
        else
          puts "ERROR: Service not found"
        end
      end
    end
  end
end

class ServiceStartCmd < CmdParse::Command
  def initialize
    $parser.data[:all_services] = false
    super('start', takes_commands: false)
    short_desc('Start services from node')
  end

  def execute(node, *services)
    nodes = []
    utils = Utils.instance

    begin
      nodes = utils.check_nodes(node)
      if nodes.count == 0
        services.insert(0, node)
        nodes << Socket.gethostname.split(".").first
      end
    rescue Errno::ECONNREFUSED # If the node is ips/proxy, is not reachable
      if node == Socket.gethostname.split(".").first
        nodes << node
      else
        services.insert(0, node)
        nodes << Socket.gethostname.split(".").first
      end
    end

    nodes.each do |n|
      node = utils.get_node(n)

      unless node
        puts "ERROR: Node not found!"
        next
      end

      systemd_services = node.attributes['redborder']['systemdservices']
      if node.role?('manager')
        services.each do |service|
          found = false
          systemd_services.each_value do |v|
            if v.include?(service)
              ret = utils.remote_cmd(n, "systemctl start #{service} &>/dev/null") ? 'started' : 'failed to start'
              puts "#{service} #{ret} on #{n}"
              found = true
            end
          end
          puts "#{service} is not found on #{n}" unless found
        end
      else
        services.each do |service|
          found = false
          systemd_services.each_value do |v|
            if v.include?(service)
              `systemctl start #{service} &>/dev/null`
              ret = $?.success? ? 'started' : 'failed to start'
              puts "#{service} #{ret} on #{n}"
              found = true
            end
          end
          puts "#{service} is not found on #{n}" unless found
        end
      end
    end
  end
end

class ServiceStopCmd < CmdParse::Command
  def initialize
    $parser.data[:all_services] = false
    super('stop', takes_commands: false)
    short_desc('Stop services from node')
  end

  def execute(node, *services)
    nodes = []
    utils = Utils.instance

    begin
      nodes = utils.check_nodes(node)
      if nodes.count == 0
        services.insert(0, node)
        nodes << Socket.gethostname.split(".").first
      end
    rescue Errno::ECONNREFUSED # If the node is ips/proxy, is not reachable
      if node == Socket.gethostname.split(".").first
        nodes << node
      else
        services.insert(0, node)
        nodes << Socket.gethostname.split(".").first
      end
    end

    nodes.each do |n|
      node = utils.get_node(n)

      unless node
        puts "ERROR: Node not found!"
        next
      end

      systemd_services = node.attributes['redborder']['systemdservices']
      if node.role?('manager')
        services.each do |service|
          found = false
          systemd_services.each_value do |v|
            if v.include?(service)
              ret = utils.remote_cmd(n, "systemctl stop #{service} &>/dev/null") ? 'stopped' : 'failed to stop'
              puts "#{service} #{ret} on #{n}"
              found = true
            end
          end
          puts "#{service} is not found on #{n}" unless found
        end
      else
        services.each do |service|
          found = false
          systemd_services.each_value do |v|
            if v.include?(service)
              `systemctl stop #{service} &>/dev/null`
              ret = $?.success? ? 'stopped' : 'failed to stop'
              puts "#{service} #{ret} on #{n}"
              found = true
            end
          end
          puts "#{service} is not found on #{n}" unless found
        end
      end
    end
  end
end

$parser.add_command(ServiceCmd.new)
