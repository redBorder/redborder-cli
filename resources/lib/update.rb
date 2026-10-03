require 'net/http'
require 'uri'
require 'tmpdir'
require 'fileutils'
require 'rubygems'

class UpdateCmd < CmdParse::Command
  DEFAULT_HOST = 'packages.redborder.com'
  CHANNELS = %w[latest testing] # special repos, they live outside /releases
  SERVICES = %w[webui rb-workers] # stopped (if running) besides chef-client
  SENSOR_PACKAGES = %w[redborder-ips redborder-intrusion]
  REPO_DIR = '/etc/yum.repos.d'

  def initialize
    super('update', takes_commands: false)
    short_desc('Update the system to another redborder release')
    options.on('-l', '--list', 'Only list the available versions') { $parser.data[:update_list] = true }
    options.on('-r', '--release VERSION', 'Version to update to (x.y.z, latest or testing)') { |v| $parser.data[:update_release] = v }
    options.on('-m', '--mirror HOST', "Packages host to use instead of #{DEFAULT_HOST}") { |h| $parser.data[:update_mirror] = h }
    options.on('-y', '--yes', 'Do not ask for confirmation') { $parser.data[:update_yes] = true }
  end

  def execute()
    current = installed_repo
    if current.nil?
      puts 'ERROR: redborder-repo package is not installed'
      exit 1
    end

    @host = ($parser.data[:update_mirror] || configured_host || DEFAULT_HOST).sub(%r{^https?://}, '').chomp('/')

    begin
      releases = available_releases
    rescue StandardError => e
      puts "ERROR: Cannot get the releases from https://#{@host}/releases/ (#{e.message})"
      exit 1
    end
    if releases.empty?
      puts "ERROR: No releases found at https://#{@host}/releases/"
      exit 1
    end

    latest = releases.last
    targets = update_targets(current[:version], releases)

    puts "Packages host:     #{@host}"
    puts "Installed repo:    #{current[:package]}"
    puts "Installed version: #{current[:version]}"
    puts "Latest release:    #{latest}"
    puts

    if CHANNELS.include?(current[:version])
      puts "This node is using the #{current[:version]} repo, so it cannot be compared against the releases."
    elsif !newer?(latest, current[:version])
      puts 'This node is already using the latest release.'
    end

    if $parser.data[:update_list]
      puts 'Available versions:'
      targets.each { |t| puts "  #{describe(t, current[:version])}" }
      return
    end

    target = $parser.data[:update_release] || ask_target(targets, current[:version])
    return if target.nil?

    unless releases.include?(target) || CHANNELS.include?(target)
      puts "ERROR: Version #{target} not found at https://#{@host}"
      exit 1
    end

    if Process.uid != 0
      puts 'ERROR: rbcli update must be run as root'
      exit 1
    end

    rpm_url = nil
    if target != current[:version]
      begin
        rpm_url = repo_rpm_url(target)
      rescue StandardError => e
        puts "ERROR: Cannot find the redborder-repo package for #{target} (#{e.message})"
        exit 1
      end
    end

    sensor = SENSOR_PACKAGES.find { |pkg| system("rpm -q #{pkg} &>/dev/null") }
    to_stop = SERVICES.select { |s| service_running?(s) }

    puts 'The following actions will be done:'
    puts "  - Stop chef-client#{to_stop.map { |s| ", #{s}" }.join}"
    puts '  - Enable the bypass on all the segments (rb_bypass.sh -b all -s on)' if sensor
    if rpm_url
      puts "  - Replace #{current[:package]} with #{File.basename(rpm_url)}"
    else
      puts "  - Keep the current repo (#{current[:package]})"
    end
    puts '  - dnf clean all && dnf update -y'
    puts sensor ? '  - Reboot the node' : '  - Start chef-client'
    puts

    unless $parser.data[:update_yes]
      print "Update this node to #{target}? [y/N]: "
      answer = $stdin.gets.to_s.strip.downcase
      unless %w[y yes].include?(answer)
        puts 'Update cancelled'
        return
      end
    end

    # The package is downloaded before touching anything so a network failure does not leave the node half updated
    rpm_file = nil
    if rpm_url
      rpm_file = File.join(Dir.mktmpdir('rbcli-update'), File.basename(rpm_url))
      step "Downloading #{rpm_url}"
      unless system('curl', '-fsSL', '--connect-timeout', '10', '-o', rpm_file, rpm_url)
        puts 'ERROR: Cannot download the redborder-repo package'
        exit 1
      end
    end

    ok = false
    begin
      step 'Stopping chef-client'
      run('systemctl stop chef-client')
      to_stop.each do |s|
        step "Stopping #{s}"
        run("systemctl stop #{s}")
      end

      if sensor
        step 'Enabling bypass'
        puts "WARNING: rb_bypass.sh exited with code #{$?.exitstatus}, check the bypass status" unless run("#{bypass_script} -b all -s on")
      end

      ok = rpm_file.nil? || replace_repo(current[:package], rpm_file)
      if ok
        step 'Cleaning dnf cache'
        run('dnf clean all')
        step 'Updating packages'
        ok = run('dnf update -y')
      end
    ensure
      FileUtils.rm_rf(File.dirname(rpm_file)) if rpm_file
      # Sensors are rebooted instead (see below), the boot takes care of starting chef-client again
      unless ok && sensor
        step 'Starting chef-client'
        run('systemctl start chef-client')
      end
    end

    puts
    unless ok
      puts 'ERROR: The update failed, check the output above'
      exit 1
    end
    puts "Node updated to #{target}"

    # A new kernel or dkms modules (pfring, bpctl) can create a network loop if the bypass is disabled
    # before the node boots with them, so the sensors are always rebooted with the bypass still enabled
    if sensor
      step 'Rebooting the node'
      run('systemctl reboot')
    end
  end

  private

  # redborder-repo carries the release in the package name: redborder-repo-<version>
  def installed_repo
    packages = `rpm -qa --qf '%{NAME}\n' 'redborder-repo*' 2>/dev/null`.split("\n")
    package = packages.find { |p| p.start_with?('redborder-repo-') }
    return nil unless package

    { package: package, version: package.sub('redborder-repo-', '') }
  end

  # Host of the installed repo, it differs from the default one when a mirror is in use
  def configured_host
    Dir["#{REPO_DIR}/redborder*.repo"].each do |file|
      File.read(file) =~ %r{^\s*baseurl\s*=\s*https?://([^/\s]+)/}
      return $1 if $1
    end
    nil
  end

  def http_get(url, redirects = 5)
    raise 'too many redirects' if redirects == 0

    uri = URI.parse(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 30) do |http|
      http.get(uri.request_uri)
    end
    case response
    when Net::HTTPSuccess then response.body
    when Net::HTTPRedirection then http_get(URI.join(url, response['location']).to_s, redirects - 1)
    else raise "HTTP #{response.code}"
    end
  end

  def available_releases
    body = http_get("https://#{@host}/releases/")
    body.scan(%r{href="(\d+(?:\.\d+)+)/"}).flatten.uniq.sort_by { |v| Gem::Version.new(v) }
  end

  def newer?(version, than)
    Gem::Version.new(version) > Gem::Version.new(than)
  end

  # Versions the node can move to: itself (only update packages), the newer releases and the special repos.
  # From a special repo there is no version to compare with, so the releases of the last series are offered.
  def update_targets(current, releases)
    if CHANNELS.include?(current)
      series = releases.last.split('.')[0, 2].join('.')
      newer = releases.select { |r| r == series || r.start_with?("#{series}.") }
    else
      newer = releases.select { |r| newer?(r, current) }
    end
    ([current] + newer + CHANNELS).uniq
  end

  def describe(target, current)
    if target == current
      "#{target} (current, only update packages)"
    elsif CHANNELS.include?(target)
      "#{target} (#{target == 'latest' ? 'unstable' : 'testing'} repo)"
    else
      target
    end
  end

  def ask_target(targets, current)
    puts 'Available versions:'
    targets.each_with_index { |t, i| printf("  %2d) %s\n", i + 1, describe(t, current)) }
    puts
    loop do
      print "Select the version to update to [1-#{targets.size}, q to quit]: "
      answer = $stdin.gets
      return nil if answer.nil? || answer.strip.downcase == 'q'

      answer = answer.strip
      return targets[answer.to_i - 1] if answer =~ /^\d+$/ && answer.to_i.between?(1, targets.size)
      return answer if targets.include?(answer)

      puts 'Invalid option'
    end
  end

  def repo_base(target)
    path = CHANNELS.include?(target) ? target : "releases/#{target}"
    rhel = `rpm -E %rhel`.strip
    arch = `rpm -E %_arch`.strip
    "https://#{@host}/#{path}/rhel/#{rhel}/#{arch}/"
  end

  def repo_rpm_url(target)
    base = repo_base(target)
    rpms = http_get(base).scan(/href="(redborder-repo-#{Regexp.escape(target)}-(\d[\d.]*)-(\d+)[^"\/]*\.rpm)"/)
    raise 'package not found' if rpms.empty?

    base + rpms.max_by { |_, version, release| [Gem::Version.new(version), release.to_i] }.first
  end

  def replace_repo(old_package, rpm_file)
    step "Removing #{old_package}"
    return false unless run("rpm -e #{old_package}")

    step "Installing #{File.basename(rpm_file)}"
    return false unless run("rpm -ivh #{rpm_file}")

    use_mirror if @host != DEFAULT_HOST
    true
  end

  # The repo packages always point to the default host
  def use_mirror
    Dir["#{REPO_DIR}/redborder*.repo"].each do |file|
      content = File.read(file)
      next unless content.include?("//#{DEFAULT_HOST}/")

      puts "Pointing #{file} to #{@host}"
      File.write(file, content.gsub("//#{DEFAULT_HOST}/", "//#{@host}/"))
    end
  end

  def service_running?(service)
    `systemctl show -p ActiveState,SubState --value #{service} 2>/dev/null`.split == %w[active running]
  end

  def bypass_script
    "#{ENV['RBBIN'] || '/usr/lib/redborder/bin'}/rb_bypass.sh"
  end

  def step(message)
    puts "==> #{message}"
  end

  def run(cmd)
    puts "+ #{cmd}" if $parser.data[:verbose]
    system(cmd)
  end
end

$parser.add_command(UpdateCmd.new)
