# The public transparency log: publishes, yanks, takedowns, namespace claims.
class AuditLogController < ApplicationController
  allow_unauthenticated_access

  def index
    @events = AuditEvent.public_log.includes(:user).limit(200)
  end
end
