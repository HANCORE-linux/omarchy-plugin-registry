# The public transparency log: publishes, yanks, takedowns, namespace claims.
class AuditLogController < ApplicationController
  allow_unauthenticated_access

  PER_PAGE = 100

  def index
    @page = [ params[:page].to_i, 1 ].max
    @events = AuditEvent.public_log.includes(:user)
      .offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @more = @events.length > PER_PAGE
    @events = @events.first(PER_PAGE)
  end
end
