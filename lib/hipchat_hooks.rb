# encoding: utf-8
require 'uri'
require 'json'

class NotificationHook < Redmine::Hook::Listener
  include IssuesHelper

  def controller_issues_new_after_save(context = {})
    issue   = context[:issue]
    project = issue.project
    return true unless hipchat_configured?(project)

    author    = User.current.name
    tracker   = issue.tracker.name
    subject   = issue.subject
    status    = issue.status.name
    assignee  = issue.assigned_to.try(:name).presence || "Unassigned"
    url       = get_url(issue)
    text      = "#{author} Created #{tracker} ##{issue.id} : #{subject} [ #{status} | #{assignee} ] #{url}"
    text     += "\n #{issue.description}" unless issue.description.blank?

    send_message(project, text)
  end

  def controller_issues_bulk_edit_after_save(context = {})
    controller_issues_edit_after_save({ :params => context[:params], :issue => context[:issue], :journal => context[:issue].current_journal})
  end

  def controller_issues_edit_after_save(context = {})
    issue   = context[:issue]
    project = issue.project
    return true unless hipchat_configured?(project)

    editor    = User.current.name
    tracker   = issue.tracker.name
    subject   = issue.subject
    url       = get_url(issue)
    text      = "#{editor} Update #{tracker} ##{issue.id}: #{subject} #{url}"

    journal = context[:journal]
    comment   = journal.try(:notes)
    text     += ": #{truncate(comment)}" if comment.present?
    details   = journal.visible_details
    details   = details_to_strings(details, true).map{ |detail| "• #{detail}" }.join("\n") if details.present?
    text     += "\n#{details}" if details.present?

    send_message(project, text)
  end

  def controller_wiki_edit_after_save(context = {})
    page    = context[:page]
    project = page.wiki.project
    return true unless hipchat_configured?(project)

    author       = User.current.name
    wiki         = page.pretty_title
    project_name = project.name
    url          = get_url(page)
    text         = "#{author} edited the #{wiki} on #{project_name} #{url}"

    send_message(project, text)
  end

  private

  def hipchat_configured?(project)
    if !project.hipchat_auth_token.empty? && !project.hipchat_room_name.empty?
      return true
    elsif Setting.plugin_redmine_hipchat[:projects] &&
          Setting.plugin_redmine_hipchat[:projects].include?(project.id.to_s) &&
          Setting.plugin_redmine_hipchat[:auth_token] &&
          Setting.plugin_redmine_hipchat[:room_name] &&
          Setting.plugin_redmine_hipchat[:endpoint]
      return true
    else
      Rails.logger.info "Not sending HipChat message - missing config"
    end
    false
  end

  def hipchat_auth_token(project)
    return project.hipchat_auth_token.presence || Setting.plugin_redmine_hipchat[:auth_token]
  end

  def hipchat_room_name(project)
    return project.hipchat_room_name.presence || Setting.plugin_redmine_hipchat[:room_name]
  end

  def hipchat_endpoint(project)
    return project.hipchat_endpoint.presence || Setting.plugin_redmine_hipchat[:endpoint]
  end

  def hipchat_notify(project)
    return project.hipchat_notify if !project.hipchat_auth_token.empty? && !project.hipchat_room_name.empty?
    Setting.plugin_redmine_hipchat[:notify]
  end

  def get_url(object)
    case object
      when Issue    then "#{Setting[:protocol]}://#{Setting[:host_name]}/issues/#{object.id}"
      when WikiPage then "#{Setting[:protocol]}://#{Setting[:host_name]}/projects/#{object.wiki.project.identifier}/wiki/#{object.title}"
    else
      Rails.logger.info "Asked redmine_hipchat for the url of an unsupported object #{object.inspect}"
    end
  end

  def send_message(project, text)
    endpoint = hipchat_endpoint(project) || 'api.hipchat.com'
    Rails.logger.info "Sending message to HipChat( https://#{endpoint} ): #{text}"
    room_name = CGI::escape(hipchat_room_name(project))
    room_token = hipchat_auth_token(project)
    uri = URI.parse("https://#{endpoint}/v2/room/#{room_name}/notification?auth_token=#{room_token}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    req = Net::HTTP::Post.new(uri.request_uri)
    req.body = {
        "message"        => text,
        "message_format" => 'text',
        "notify"         => hipchat_notify(project) ? true : false
    }.to_json

    req['Content-Type'] = 'application/json'
    Rails.logger.info "Before HipChat Begin Http.. #{req.body} (#{uri.request_uri}"
    begin
      res = http.start do |connection|
        connection.request(req)
      end
    rescue Net::HTTPBadResponse => e
      Rails.logger.error "Error hitting HipChat API: #{e}"
    end
    Rails.logger.info "HipChat Result: #{res.body}"
  end

  def truncate(text, length = 20, end_string = '…')
    return unless text
    words = text.split()
    words[0..(length-1)].join(' ') + (words.length > length ? end_string : '')
  end
end
