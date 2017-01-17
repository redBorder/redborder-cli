#!/usr/bin/env ruby

require 'cmdparse'

$parser = CmdParse::CommandParser.new(handle_exceptions: :no_help)

Dir["#{ENV['RBLIB']}/red/*.rb"].each { |file| require file }

$parseb.global_options do |opt|
	opt.on("-v","--verbose","Enable verbosity") do
		$parser.data[:verbose] = true
	end
end

$parser.add_command(CmdParse::HelpCommand.new)

$parser.parse

