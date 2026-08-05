# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# The one operator account this app has (see the `authentication` capability -- no self-service
# registration). find_or_initialize_by + assign + save, not find_or_create_by!, so that re-running
# db:seed after rotating ADMIN_PASSWORD actually updates the existing user's password instead of
# being a no-op against the already-existing row.
admin = User.find_or_initialize_by(email_address: ENV.fetch("ADMIN_EMAIL"))
admin.password = ENV.fetch("ADMIN_PASSWORD")
admin.save!
