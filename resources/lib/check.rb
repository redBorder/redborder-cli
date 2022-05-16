require "getopt/std"
require_relative "/usr/lib/redborder/lib/check/check_functions.rb"

USAGE = <<ENDUSAGE

Usage: check [-h] [-s <service_name>] [-o <output_file>] [-u <s3path>] [-k <X>] [-c] [-q] [-e]

ENDUSAGE

HELP = <<ENDHELP
   service <service_name>      Show only information about this service name.
   output_file <output_file>   Stdout to this file.
   upload <s3path>             Upload output to this s3 path.
   keep <X>                    Keep last X files into s3.
   colorless                   Do not use colors.
   extended                    Show extended cluster information.
   quiet                       Be quiet.

ENDHELP

ARGS = { :colorless => false, :extended=> false, :quiet=> false, :service => nil}   # Setting default values
UNFLAGGED_ARGS = [ :directory ]     # Bare arguments (no flag)

def print_date_on_file(output_file)
  file = File.open(output_file, "w")
  columns =  get_stty_columns
  if colorless
    file.puts("#" * columns)
    file.puts("DATE:  " + time)
    file.puts("#" * columns)
  else
    file.puts("\e[36m" +  "#" * columns)
    file.puts("\e[34m" + "DATE:  " + time + "\e[36m")
    file.puts("#" * columns)
  end
  file.close
end

class CheckCmd < CmdParse::Command
  def initialize
    super('check')
    short_desc('Check status of all nodes\'s services in the cluster')
    add_command(CheckStatusCmd.new, default: true)
    add_command(CheckListCmd.new)
    add_command(CheckHelpCmd.new)
  end
end

class CheckHelpCmd < CmdParse::Command
  def initialize
    super('help', takes_commands: false)
  end

  def execute
    puts USAGE
    puts HELP
  end
end

class CheckListCmd < CmdParse::Command
  def initialize
    super('list', takes_commands: false)
  end

  def execute
    list = []
    commons = %w[hd install io killed licenses memory]

    commons.each { | s |  list.push(s)}

    check_dir = "/usr/lib/redborder/lib/check"

    directories = Dir.entries(check_dir).select{
      |entry| File.directory? File.join(check_dir,entry) and
        !(entry == '.' || entry == '..' || entry == 'commons')}

    directories.each { | s |  list.push(s)}

    logit "Checks available:\n"

    list.each { |check| logit("  -" + check) }
  end
end

class CheckStatusCmd < CmdParse::Command
  def initialize
    super('status', takes_commands: false)
  end

  def execute( *argv )
    next_arg = UNFLAGGED_ARGS.first
    argv.each do |arg|
      case arg
      when 'service'       then next_arg           = :service
      when 'output_file'   then next_arg           = :output_file
      when 'upload'        then next_arg           = :upload
      when 'keep'          then next_arg           = :keep
      when 'colorless'     then ARGS[:colorless]   = true
      when 'extended'      then ARGS[:extended]    = true
      when 'quiet'         then ARGS[:quiet]       = true
      else
        if next_arg
          ARGS[next_arg] = arg
          UNFLAGGED_ARGS.delete( next_arg )
        end
        next_arg = UNFLAGGED_ARGS.first
      end
    end

    script_commands = ""

    #ARGS
    service = ARGS[:service]
    if ARGS[:output_file]
      output_file = ARGS[:output_file]
      File.delete(output_file) if File.exist?(output_file)
      File.new(output_file, "w").close()
    else
      output_file = "/dev/null"
    end
    upload = ARGS[:upload]
    keep = ARGS[:keep]
    colorless = ARGS[:colorless]
    script_commands += " -c" if colorless
    extended = ARGS[:extended]
    script_commands += " -e" if extended
    quiet = ARGS[:quiet]
    script_commands += " -q" if quiet

    time = Time.utc(*Time.new.to_a).to_s
    has_errors = false

    commons = %w[hd install io killed licenses memory]
    check_dir = "/usr/lib/redborder/lib/check"
    scripts_path = []

    title_ok("DATE:  " + time,colorless,quiet)

    print_date_on_file(output_file) if output_file != "/dev/null"

    if service.nil?

      #Collecting all scripts in "/usr/lib/redborder/lib/check/commons"
      commons.each do |script|
        scripts_path.push(File.join(check_dir,"commons","rb_check_" + script + ".rb"))
      end

      #Collecting all scripts in /usr/lib/redborder/lib/check
      # They must have the following directory structure:
      #   /usr/lib/redborder/lib/check/<script>
      #   ├── rb_check_<script>_functions.rb
      #   └── rb_check_<script>.rb
      directories = Dir.entries(check_dir).select{
        |entry| File.directory? File.join(check_dir,entry) and
          !(entry == '.' || entry == '..' || entry == 'commons') }
      directories.each do | dir |
        scripts = Dir.entries(File.join(check_dir,dir)).select{|entry|
          !(entry == '.' || entry == '..' || entry.include?('functions')) }
        scripts.sort.each do |s|
          scripts_path.push(File.join(check_dir,dir,s))
        end
      end
    else
      if commons.include? service
        scripts_path.push(File.join(check_dir,"commons","rb_check_" + service + ".rb"))

      elsif File.directory? File.join(check_dir,service)
        scripts_path.push(File.join(check_dir,service,"rb_check_" + service + ".rb"))

      else
        logit("Service #{service} has not got scripts to check")
        exit 1
      end
    end

    scripts_path.each do | script |
      result = `#{script} #{script_commands} | tee #{output_file}`
      return_value = $?.exitstatus
      has_errors = true if return_value != 0
      puts result
    end
    exit 1 if has_errors
  end
end
$parser.add_command(CheckCmd.new)
