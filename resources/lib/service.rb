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
    add_command(ServiceAllCmd.new, default: false)
  end
end

class ServiceAllCmd < CmdParse::Command
  RESET, GREEN, YELLOW, BLUE, RED, BLINK =
    "\e[0m", "\e[32m", "\e[33m", "\e[34m", "\e[31m", "\e[5m"

  def initialize
    $parser.data[:show_runtime] = true
    $parser.data[:no_color]     = false
    super('all', takes_commands: false)
    short_desc('List all services on all managers')
    options.on('-q', '--quiet',    'Hide runtime')        { $parser.data[:show_runtime] = false }
    options.on('-n', '--no-color', 'Disable color output') { $parser.data[:no_color]     = true }
  end

  def execute
    require 'net/ssh'
    if $parser.data[:no_color]
      red = green = yellow = blue = reset = blink = ''
    else
      red, green, yellow, blue, reset, blink = RED, GREEN, YELLOW, BLUE, RESET, BLINK
    end

    utils = Utils.instance
    node = utils.get_node(Socket.gethostname.split('.').first)
    @cached_cluster     = node['redborder']['managers_per_services']
    @cached_translation = node['redborder']['systemdservices']

    services = @cached_cluster.keys.sort.flat_map { |k| @cached_translation.fetch(k, []) }.uniq
    external_services = JSON.parse(File.read('/var/chef/data/data_bag/rBglobal/external_services.json')) rescue {}
    hosts = `serf members`.lines.map { |l| l.split.first if l.split[2] == 'alive' }.compact.sort
    return warn('No live managers found') if hosts.empty?

    running = stopped = external = errors = 0

    services_esc = services.map { |s| Shellwords.escape(s) }.join(' ')
    show_rt      = $parser.data[:show_runtime] ? '1' : '0'
    remote = <<~BASH
      services=(#{services_esc})
      for s in "${services[@]}"; do
        st=$(systemctl is-active "$s" 2>/dev/null || echo unknown)
        st=$(echo "$st" | head -n 1)
        en=$(systemctl is-enabled "$s" 2>/dev/null || echo disabled)
        en=$(echo "$en" | head -n 1)
        rt="N/A"
        if [ "$st" = "active" ] && [ "#{show_rt}" = "1" ]; then
          rt=$(systemctl status "$s" | grep 'Active:' | awk '{for(i=9;i<=NF;i++) printf $i " "; print ""}')
        fi
        printf "%s|%s|%s|%s\n" "$s" "$st" "$en" "$rt"
      done
    BASH

    host_data = {}
    hosts.each do |host|
      Net::SSH.start(host, 'root',
                     keys: ["/root/.ssh/rsa"],
                     non_interactive: true,
                     timeout: 5,
                     verify_host_key: :never) do |ssh|
        out = ssh.exec!(remote)
        host_data[host] = out.lines.each_with_object({}) do |l, h|
          svc, st, en, rt = l.chomp.split('|', 4)
          h[svc] = [st, en, rt]
        end
      end
    end

    width = 30 + 35 * hosts.size
    puts '-' * width
    printf "%-30s", 'Service'
    hosts.each { |h| printf "%-35s", h }
    puts
    puts '-' * width

    host_totals = Array.new(hosts.size, 0)

    services.each do |svc|
      printf "%-30s", "#{svc}:"
      hosts.each_with_index do |host, idx|
        raw_st, raw_en, rt = host_data[host][svc] || ['unknown', 'unknown', 'N/A']

        st = case
          when raw_st == 'active'
            'running'
          when %w[inactive failed].include?(raw_st) && raw_en == 'disabled'
            'not running'
          when %w[inactive failed].include?(raw_st) && raw_en == 'enabled'
            'not running!!'
          else
            'unknown'
          end

        if (external_services.include?(svc) && external_services[svc] == 'external') ||
           (svc == 'minio' && external_services['s3'] == 'external')
          st = 'external'
        end

        if %w[running not running not running!! external].include?(st)
          host_totals[idx] += 1
        end

        case st
        when 'running'       then running += 1
        when 'not running'   then stopped += 1
        when 'external'      then external += 1
        when 'not running!!' then errors += 1
        end

        host_col_width     = 35
        status_col_width   = 14
        runtime_col_width  = host_col_width - status_col_width - 1

        rt_str = rt.strip
        rt_str = "N/A" if rt_str.empty?

        status_str = st.ljust(status_col_width)
        runtime_str = rt_str.rjust(runtime_col_width)

        color = case st
                when 'running'       then green
                when 'not running'   then yellow
                when 'not running!!' then red
                else                    red
                end

        if $parser.data[:show_runtime] && rt =~ /^\d+\s*s/
          runtime_str = "#{blink}#{runtime_str}#{reset}"
        else
          runtime_str = "#{color}#{runtime_str}#{reset}"
        end
        status_str = "#{color}#{status_str}#{reset}"

        print status_str + runtime_str + "|"
      end
      puts
    end

    puts '-' * width
    printf "%-30s", 'Total:'
    host_totals.each do |count|
      printf "%-35s", count
    end
    puts
    puts '-' * width
    printf("Running: %d  /  Stopped: %d  /  External: %d  /  Errors: %d\n", running, stopped, external, errors)
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
    $parser.data[:show_memory] = true
    $parser.data[:no_color] = false
    super('list', takes_commands: false)
    short_desc('List services from node')
    options.on('-q', '--quiet', 'Show list without runtime or memory') {
      $parser.data[:show_runtime] = false
      $parser.data[:show_memory] = false
    }
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
    total_memory = 0

    # Paint service list
    if $parser.data[:show_runtime] && $parser.data[:show_memory]
      printf("=========================================== Services =====================================================\n")
      printf("%-33s %-33s %-15s %-10s %-33s\n", "Service", "Status(#{node_name})", "Runtime", "Memory", "Cgroup")
      printf("----------------------------------------------------------------------------------------------------------\n")
    elsif $parser.data[:show_runtime]
      printf("================================= Services =========================================\n")
      printf("%-33s %-33s %-10s %-33s\n", "Service", "Status(#{node_name})", "Runtime", "Cgroup")
      printf("------------------------------------------------------------------------------------\n")
    elsif $parser.data[:show_memory]
      printf("================================= Services ========================================\n")
      printf("%-33s %-33s %-10s %-33s\n", "Service", "Status(#{node_name})", "Memory", "Cgroup")
      printf("-----------------------------------------------------------------------------------\n")
    else
      printf("=========================== Services ============================\n")
      printf("%-33s %-10s\n", "Service", "Status(#{node_name})")
      printf("-----------------------------------------------------------------\n")
    end

    services.uniq.sort.each do |systemd_service, enabled|
      cgroup = get_cgroup(systemd_service) || "N/A"

      if systemd_service == 'snort3' # Special check for intrusion sensor
        status_output = `service snort3 status 2>/dev/null`
        if $?.success?
          ret = "running"
          running += 1

          snort_processes = `ps aux | grep snort | grep -v grep`
          runtimes = []
          total_rss_kb = 0

          snort_processes.each_line do |line|
            parts = line.split
            next unless parts.size >= 6

            rss_kb = parts[5].to_i
            total_rss_kb += rss_kb

            pid = parts[1]
            etime = `ps -p #{pid} -o etime=`.strip
            if etime =~ /^(\d+)-(\d+):(\d+):/
              days, hours, mins = $1.to_i, $2.to_i, $3.to_i
              runtimes << "#{days * 24 + hours}h #{mins}min ago"
            elsif etime =~ /^(\d+):(\d+):/
              hours, mins = $1.to_i, $2.to_i
              runtimes << "#{hours}h #{mins}min ago"
            elsif etime =~ /^(\d+):(\d+)$/
              mins = $1.to_i
              runtimes << "#{mins}min ago"
            elsif etime =~ /^(\d+)$/
              secs = $1.to_i
              runtimes << "#{secs}s ago"
            else
              runtimes << etime
            end
          end

          memory_used =
            if total_rss_kb > 0
              kb = total_rss_kb
              if kb > 1_048_576
                "#{(kb / 1024.0 / 1024.0).round(2)}G"
              elsif kb > 1024
                "#{(kb / 1024.0).round(2)}M"
              else
                "#{kb}K"
              end
            else
              "0B"
            end

          runtime = runtimes.min || "N/A"
          total_memory += total_rss_kb * 1024 # bytes

          if $parser.data[:show_runtime] && $parser.data[:show_memory]
            if runtime.match?(/^\d+\s*s/)
              printf("%-33s #{green}%-33s#{reset} #{blink}%-15s#{reset} %-10s %-25s\n",
                    "#{systemd_service}:", ret, runtime, memory_used, cgroup)
            else
              printf("%-33s #{green}%-33s#{reset} %-15s %-10s %-25s\n",
                    "#{systemd_service}:", ret, runtime, memory_used, cgroup)
            end
          elsif $parser.data[:show_runtime]
            if runtime.match?(/^\d+\s*s/)
              printf("%-33s #{green}%-33s#{reset} #{blink}%-15s#{reset} %-25s\n",
                    "#{systemd_service}:", ret, runtime, cgroup)
            else
              printf("%-33s #{green}%-33s#{reset} %-15s %-25s\n",
                    "#{systemd_service}:", ret, runtime, cgroup)
            end
          elsif $parser.data[:show_memory]
            printf("%-33s #{green}%-33s#{reset} %-10s %-25s\n",
                  "#{systemd_service}:", ret, memory_used, cgroup)
          else
            printf("%-33s #{green}%-33s#{reset} %-25s\n",
                  "#{systemd_service}:", ret, cgroup)
          end
        else
          ret = "not running!!"
          errors += 1
          runtime = "N/A"
          memory_used = "0B"

          if $parser.data[:show_runtime] && $parser.data[:show_memory]
            printf("%-33s #{red}%-33s#{reset} %-15s %-10s %-25s\n",
                  "#{systemd_service}:", ret, runtime, memory_used, cgroup)
          elsif $parser.data[:show_runtime]
            printf("%-33s #{red}%-33s#{reset} %-15s %-25s\n",
                  "#{systemd_service}:", ret, runtime, cgroup)
          elsif $parser.data[:show_memory]
            printf("%-33s #{red}%-33s#{reset} %-10s %-25s\n",
                  "#{systemd_service}:", ret, memory_used, cgroup)
          else
            printf("%-33s #{red}%-33s#{reset} %-25s\n",
                  "#{systemd_service}:", ret, cgroup)
          end
        end

      elsif system("systemctl status #{systemd_service} &>/dev/null")
        ret = "running"
        running += 1

        runtime = `systemctl status #{systemd_service} | grep 'Active:' | awk '{for(i=9;i<=NF;i++) printf $i " "; print ""}'`.strip
        memory_used = `systemctl status #{systemd_service} | grep 'Memory:' | sed 's/.*Memory:[[:space:]]*//'`.strip
        memory_used = memory_used = '0B' if memory_used.to_s.empty?
        total_memory += parse_memory_to_bytes(memory_used)

        if $parser.data[:show_runtime] && $parser.data[:show_memory]
          if runtime.match?(/^\d+\s*s/)
            printf("%-33s #{green}%-33s#{reset} #{blink}%-15s#{reset} %-10s %-25s\n",
                  "#{systemd_service}:", ret, runtime, memory_used, cgroup)
          else
            printf("%-33s #{green}%-33s#{reset} %-15s %-10s %-25s\n",
                  "#{systemd_service}:", ret, runtime, memory_used, cgroup)
          end
        elsif $parser.data[:show_runtime]
          if runtime.match?(/^\d+\s*s/)
            printf("%-33s #{green}%-33s#{reset} #{blink}%-15s#{reset} %-25s\n",
                  "#{systemd_service}:", ret, runtime, cgroup)
          else
            printf("%-33s #{green}%-33s#{reset} %-15s %-25s\n",
                  "#{systemd_service}:", ret, runtime, cgroup)
          end
        elsif $parser.data[:show_memory]
          printf("%-33s #{green}%-33s#{reset} %-10s %-25s\n",
                "#{systemd_service}:", ret, memory_used, cgroup)
        else
          printf("%-33s #{green}%-33s#{reset} %-25s\n",
                "#{systemd_service}:", ret, cgroup)
        end

      elsif !enabled
        ret = "not running"
        stopped += 1
        runtime = "N/A"
        memory_used = "0B"

        if $parser.data[:show_runtime] && $parser.data[:show_memory]
          printf("%-33s #{yellow}%-33s#{reset} %-15s %-10s %-25s\n",
                "#{systemd_service}:", ret, runtime, memory_used, cgroup)
        elsif $parser.data[:show_runtime]
          printf("%-33s #{yellow}%-33s#{reset} %-15s %-25s\n",
                "#{systemd_service}:", ret, runtime, cgroup)
        elsif $parser.data[:show_memory]
          printf("%-33s #{yellow}%-33s#{reset} %-10s %-25s\n",
                "#{systemd_service}:", ret, memory_used, cgroup)
        else
          printf("%-33s #{yellow}%-33s#{reset} %-25s\n",
                "#{systemd_service}:", ret, cgroup)
        end

      elsif (external_services.include?(systemd_service) && external_services[systemd_service] == "external") ||
            (systemd_service == 'minio' && external_services.include?('s3') && external_services['s3'] == 'external')
        ret = "external"
        external += 1
        runtime = "N/A"
        memory_used = "0B"

        if $parser.data[:show_runtime] && $parser.data[:show_memory]
          printf("%-33s #{blue}%-33s#{reset} %-15s %-10s %-25s\n",
                "#{systemd_service}:", ret, runtime, memory_used, cgroup)
        elsif $parser.data[:show_runtime]
          printf("%-33s #{blue}%-33s#{reset} %-15s %-25s\n",
                "#{systemd_service}:", ret, runtime, cgroup)
        elsif $parser.data[:show_memory]
          printf("%-33s #{blue}%-33s#{reset} %-10s %-25s\n",
                "#{systemd_service}:", ret, memory_used, cgroup)
        else
          printf("%-33s #{blue}%-33s#{reset} %-25s\n",
                "#{systemd_service}:", ret, cgroup)
        end

      else
        ret = "not running!!"
        errors += 1
        runtime = "N/A"
        memory_used = "0B"

        if $parser.data[:show_runtime] && $parser.data[:show_memory]
          printf("%-33s #{red}%-33s#{reset} %-15s %-10s %-25s\n",
                "#{systemd_service}:", ret, runtime, memory_used, cgroup)
        elsif $parser.data[:show_runtime]
          printf("%-33s #{red}%-33s#{reset} %-15s %-25s\n",
                "#{systemd_service}:", ret, runtime, cgroup)
        elsif $parser.data[:show_memory]
          printf("%-33s #{red}%-33s#{reset} %-10s %-25s\n",
                "#{systemd_service}:", ret, memory_used, cgroup)
        else
          printf("%-33s #{red}%-33s#{reset} %-25s\n",
                "#{systemd_service}:", ret, cgroup)
        end
      end
    end

    if $parser.data[:show_runtime] && $parser.data[:show_memory]
      printf("----------------------------------------------------------------------------------------------------------\n")
    elsif $parser.data[:show_runtime] || $parser.data[:show_memory]
      printf("------------------------------------------------------------------------------------\n")
    else
      printf("-----------------------------------------------------------------\n")
    end

    units = ['B', 'K', 'M', 'G', 'T', 'P']
    if total_memory.zero?
      total_memory_formatted = '0B'
    else
      total_memory = total_memory.to_f
      unit = 0
      while total_memory > 1024 && unit < units.size - 1
        total_memory /= 1024
        unit += 1
      end
      total_memory_formatted = Kernel.format('%.2f%s', total_memory, units[unit])
    end

    if $parser.data[:show_memory] && $parser.data[:show_runtime]
      printf("%-33s %-10s %49s\n","Total:", services.count, total_memory_formatted)
    elsif $parser.data[:show_memory]
      printf("%-33s %-10s %28s\n","Total:", services.count, total_memory_formatted)
    else
      printf("%-33s %-10s\n","Total:", services.count)
    end

    if $parser.data[:show_runtime] && $parser.data[:show_memory]
      printf("----------------------------------------------------------------------------------------------------------\n")
    elsif $parser.data[:show_runtime] || $parser.data[:show_memory]
      printf("------------------------------------------------------------------------------------\n")
    else
      printf("-----------------------------------------------------------------\n")
    end 
    printf("Running: #{running}  /  Stopped: #{stopped}  /  External: #{external}  /  Errors: #{errors}\n\n")
    manager_node = utils.get_node(node_name)
    if manager_node && manager_node['uptime_seconds'].is_a?(Numeric)
      printf("#{node_name} runtime: #{manager_node['uptime']}\n")
      printf("#{node_name} start time: #{Time.now - manager_node['uptime_seconds']}\n\n")
    else
      printf("Error getting manager node\n\n")
    end
  end

  def parse_memory_to_bytes(memory_str)
    return 0 if memory_str.nil? || memory_str.strip.empty?

    if memory_str =~ /([\d.]+)\s*([BKMGTP]?)/i
      value = $1.to_f
      unit  = $2.upcase

      multiplier = case unit
                   when '', 'B' then 1
                   when 'K' then 1024
                   when 'M' then 1024**2
                   when 'G' then 1024**3
                   when 'T' then 1024**4
                   when 'P' then 1024**5
                   else 1
                   end

      (value * multiplier).to_i
    else
      0
    end
  end

  # Return cgroup path for a systemd unit, or nil if unknown
  def get_cgroup(unit)
    # Normalize unit name
    unit = unit.include?('.') ? unit : "#{unit}.service"

    if unit == "snort3.service"
      pid = `pgrep -o snort`.strip
      return "N/A" if pid.empty?

      path = "/proc/#{pid}/cgroup"
      return "N/A" unless File.exist?(path)

      # Read cgroup file and find the slice
      cg_lines = File.read(path).split("\n")
      slices = cg_lines.map { |l| l.split(":").last.split("/") }.flatten.select { |p| p.end_with?(".slice") }
      slice = slices.last
      return slice || "N/A"
    end

    cg = `systemctl show #{unit} -p ControlGroup --value 2>/dev/null`.strip
    return "N/A" if cg.empty?

    parts = cg.split('/')
    slice = parts.find { |p| p.end_with?('.slice') }
    slice || cg || "N/A"
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
    protected_services = ['s3', 'redis', 'postgresql'] # Mandatory services that cannot be disabled if only one node is running

    if service == 'postgresql' && !Dir.exist?('/var/lib/pgsql/data')
      puts 'PostgreSQL already disabled.'
      return
    elsif service == 'postgresql' && utils.postgres_master?
      puts 'ERROR: Cannot disable PostgreSQL on this node because it is the master.'
      return
    end

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

    if protected_services.include?(service)
      total_enabled_nodes = 0
      utils.check_nodes("all").each do |n|
        n_node = utils.get_node(n)
        next unless n_node
        role = Chef::Role.load(n)
        
        service_role = if role.override_attributes.dig('redborder','services',service).nil?
                        n_node['redborder']['services'][service]
                      else
                        role.override_attributes["redborder"]["services"][service]
                      end
        
        total_enabled_nodes += 1 if service_role
      end

      if total_enabled_nodes <= 1
        puts "ERROR: Service '#{service}' is enabled on only one node. Cannot disable it."
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

    if services.include?('postgresql') && !Dir.exist?('/var/lib/pgsql/data')
      puts 'PostgreSQL already disabled.'
      return
    elsif services.include?('postgresql') && utils.postgres_master?
      puts 'ERROR: Cannot stop PostgreSQL on this node because it is the master.'
      return
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
