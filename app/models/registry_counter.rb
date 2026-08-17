# Named monotonic counters (single-row atomic increment).
class RegistryCounter < ApplicationRecord
  def self.next!(name)
    counter = find_or_create_by!(name: name)
    counter.with_lock do
      counter.update!(value: counter.value + 1)
      counter.value
    end
  end
end
