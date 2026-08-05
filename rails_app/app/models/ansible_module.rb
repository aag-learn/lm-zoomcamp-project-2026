class AnsibleModule < ApplicationRecord
  has_many :chunks, dependent: :destroy
end
