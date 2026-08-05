namespace :db do
  namespace :grafana_reader do
    desc "Ensure the read-only grafana_reader Postgres role exists, granted SELECT on the tables Grafana's dashboard reads"
    task ensure: :environment do
      connection = ActiveRecord::Base.connection
      password = ENV.fetch("GRAFANA_DB_PASSWORD")

      begin
        connection.execute("CREATE ROLE grafana_reader LOGIN PASSWORD #{connection.quote(password)}")
        puts "Created grafana_reader role"
      rescue ActiveRecord::StatementInvalid => e
        raise unless e.message.include?("already exists")

        puts "grafana_reader role already exists"
      end

      %w[retrieval_logs feedbacks messages].each do |table|
        connection.execute("GRANT SELECT ON #{table} TO grafana_reader")
      end
      puts "Granted SELECT on retrieval_logs, feedbacks, messages to grafana_reader"
    end
  end
end
