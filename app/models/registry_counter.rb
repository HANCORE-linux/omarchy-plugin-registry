# Named monotonic counters (single-row atomic increment). `floor` lets callers
# anchor the counter to wall-clock milliseconds: a database restored from an
# older backup resumes BELOW real time, and the floor pulls the next value
# back above every generation clients have already seen.
class RegistryCounter < ApplicationRecord
  def self.next!(name, floor: 0)
    counter = find_or_create_by!(name: name)
    counter.with_lock do
      counter.update!(value: [ counter.value + 1, floor ].max)
      counter.value
    end
  end
end
