# Base for everything in the `security` database (db/security_schema.rb).
class Security::Record < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: {writing: :security}
end
