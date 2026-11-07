# Subprocess-only fixture; launched by test/deploy/mail_compose_test.rb.
# Standalone: ruby test/deploy/mail_compose_test.rb (no Rails/Docker).
require "yaml"

root = File.expand_path("../../..", __dir__)
config = YAML.load_file(File.join(root, "compose.yaml"), aliases: true)
services = config.fetch("services")
overlay = YAML.load_file(File.join(root, "compose.mail.yaml"))
mail = overlay.fetch("services").fetch("mail")
raise "Base deployment must not define mail infrastructure" if services.key?("mail") || config.fetch("networks").key?("mailnet")
raise "External services must not join mail network" if services.values.any? { |service| service.fetch("networks", []).include?("mailnet") }
raise "SMTP must not be public" if mail.key?("ports") || mail.key?("network_mode")
raise "Queue must persist" unless mail.fetch("volumes").include?("mail_queue:/var/spool/postfix")
members = overlay.fetch("services").select { |_, service| service.fetch("networks", []).include?("mailnet") }.keys.sort
raise "Only app and relay may share network" unless members == %w[mail web worker]
%w[web worker].each do |name|
  raise "External mail must not depend on Postfix" if services[name].fetch("depends_on").key?("mail")
end
raise "Mail must be opt-in" unless mail["profiles"] == [ "local-mail" ]
subnet = overlay.dig("networks", "mailnet", "ipam", "config", 0, "subnet")
raise "Trust must match Docker network" unless subnet == mail.dig("environment", "MAIL_NETWORK")
raise "Local clone must not send mail" if YAML.load_file(File.join(root, "compose.local.yaml"))["services"].key?("mail")
server = File.read(File.join(root, "deploy/server"))
raise "Resolve mail after bootstrap" unless server.index('runner deploy/mail_mode.rb') > server.index('runner deploy/configure_mail.rb')
raise "Seed after migrations" unless server.index('runner deploy/configure_mail.rb') > server.index('db:prepare')
puts "Mail deployment checks passed."
