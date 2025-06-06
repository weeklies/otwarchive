class AbuseReport < ApplicationRecord
  validates :email, email_format: { allow_blank: false }
  validates_presence_of :language
  validates_presence_of :summary
  validates_presence_of :comment
  validates :url, presence: true, length: { maximum: 2080 }
  validate :url_is_not_over_reported
  validate :email_is_not_over_reporting
  validates_length_of :summary, maximum: ArchiveConfig.FEEDBACK_SUMMARY_MAX,
                                too_long: ts('must be less than %{max}
                                             characters long.',
                                max: ArchiveConfig.FEEDBACK_SUMMARY_MAX_DISPLAYED)

  before_validation :truncate_url, if: :will_save_change_to_url?

  # It doesn't have the type set properly in the database, so override it here:
  attribute :summary_sanitizer_version, :integer, default: 0

  # Truncates the user-provided URL to the maximum we can store in the database. We don't want to reject reports with very long URLs, but we need to do
  # something to avoid a 500 error for long URLs.
  def truncate_url
    self.url = url[0..2079]
  end

  validate :check_for_spam
  def check_for_spam
    approved = logged_in_with_matching_email? || !Akismetor.spam?(akismet_attributes)
    errors.add(:base, ts("This report looks like spam to our system!")) unless approved
  end

  def logged_in_with_matching_email?
    User.current_user.present? && User.current_user.email.downcase == email.downcase
  end

  def akismet_attributes
    name = username ? username : ""
    # If the user is logged in and we're sending info to Akismet, we can assume
    # the email does not match.
    role = User.current_user.present? ? "user-with-nonmatching-email" : "guest"
    {
      comment_type: "contact-form",
      key: ArchiveConfig.AKISMET_KEY,
      blog: ArchiveConfig.AKISMET_NAME,
      user_ip: ip_address,
      user_role: role,
      comment_author: name,
      comment_author_email: email,
      comment_content: comment
    }
  end

  scope :by_date, -> { order('created_at DESC') }

  # Standardize the format of work, chapter, and profile URLs to get it ready
  # for the url_is_not_over_reported validation.
  # Work URLs: "works/123"
  # Chapter URLs: "chapters/123"
  # Profile URLs: "users/username"
  before_validation :standardize_url, on: :create
  def standardize_url
    return unless url =~ %r{((chapters|works)/\d+)} || url =~ %r{(users\/\w+)}

    self.url = add_scheme_to_url(url)
    self.url = clean_url(url)
    self.url = add_work_id_to_url(self.url)
  end

  def add_scheme_to_url(url)
    uri = Addressable::URI.parse(url)
    return url unless uri.scheme.nil?

    "https://#{uri}"
  end

  # Clean work or profile URLs so we can prevent the same URLs from getting
  # reported too many times.
  # If the URL ends without a / at the end, add it: url_is_not_over_reported
  # uses the / so "/works/1234" isn't a match for "/works/123"
  def clean_url(url)
    uri = Addressable::URI.parse(url)

    uri.query = nil
    uri.fragment = nil
    uri.path += "/" unless uri.path.end_with? "/"

    uri.to_s
  end

  # Get the chapter id from the URL and try to get the work id
  # If successful, add the work id to the URL in front of "/chapters"
  def add_work_id_to_url(url)
    return url unless url =~ %r{(chapters/\d+)} && url !~ %r{(works/\d+)}

    chapter_regex = %r{(chapters/)(\d+)}
    regex_groups = chapter_regex.match url
    chapter_id = regex_groups[2]
    work_id = Chapter.find_by(id: chapter_id).try(:work_id)

    return url if work_id.nil?

    uri = Addressable::URI.parse(url)
    uri.path = "/works/#{work_id}" + uri.path

    uri.to_s
  end

  validate :url_on_archive, if: :will_save_change_to_url?
  def url_on_archive
    parsed_url = Addressable::URI.heuristic_parse(url)
    errors.add(:url, :not_on_archive) unless ArchiveConfig.PERMITTED_HOSTS.include?(parsed_url.host)
  rescue Addressable::URI::InvalidURIError
    errors.add(:url, :not_on_archive)
  end

  def email_and_send
    UserMailer.abuse_report(id).deliver_later
    send_report
  end

  def send_report
    return unless zoho_enabled?

    reporter = AbuseReporter.new(
      title: summary,
      description: comment,
      language: language,
      email: email,
      username: username,
      ip_address: ip_address,
      url: url,
      creator_ids: creator_ids
    )
    response = reporter.send_report!
    ticket_id = response["id"]
    return if ticket_id.blank?

    attach_work_download(ticket_id)
  end

  def creator_ids
    work_id = reported_work_id
    return unless work_id

    work = Work.find_by(id: work_id)
    return "deletedwork" unless work

    ids = work.pseuds.pluck(:user_id).push(*work.original_creators.pluck(:user_id)).uniq.sort
    ids.prepend("orphanedwork") if ids.delete(User.orphan_account.id)
    ids.join(", ")
  end

  # ID of the reported work, unless the report is about comment(s) on the work
  def reported_work_id
    comments = url[%r{/comments/}, 0]
    url[%r{/works/(\d+)}, 1] if comments.nil?
  end

  def attach_work_download(ticket_id)
    work_id = reported_work_id
    return unless work_id

    work = Work.find_by(id: work_id)
    ReportAttachmentJob.perform_later(ticket_id, work) if work
  end

  # if the URL clearly belongs to a work (i.e. contains "/works/123")
  # or a user profile (i.e. contains "/users/username")
  # make sure it isn't reported more than ABUSE_REPORTS_PER_WORK_MAX
  # or ABUSE_REPORTS_PER_USER_MAX times per month
  def url_is_not_over_reported
    message = ts('This page has already been reported. Our volunteers only
                 need one report in order to investigate and resolve an issue,
                 so please be patient and do not submit another report.')
    if url =~ /\/works\/\d+/
      # use "/works/123/" to avoid matching chapter or external work ids
      work_params_only = url.match(/\/works\/\d+\//).to_s
      existing_reports_total = AbuseReport.where('created_at > ? AND
                                                 url LIKE ?',
                                                 1.month.ago,
                                                 "%#{work_params_only}%").count
      if existing_reports_total >= ArchiveConfig.ABUSE_REPORTS_PER_WORK_MAX
        errors.add(:base, message)
      end
    elsif url =~ /\/users\/\w+/
      user_params_only = url.match(/\/users\/\w+\//).to_s
      existing_reports_total = AbuseReport.where('created_at > ? AND
                                                 url LIKE ?',
                                                 1.month.ago,
                                                 "%#{user_params_only}%").count
      if existing_reports_total >= ArchiveConfig.ABUSE_REPORTS_PER_USER_MAX
        errors.add(:base, message)
      end
    end
  end

  def email_is_not_over_reporting
    existing_reports_total = AbuseReport.where("created_at > ? AND
                                               email LIKE ?",
                                               1.day.ago,
                                               email).count
    return if existing_reports_total < ArchiveConfig.ABUSE_REPORTS_PER_EMAIL_MAX

    errors.add(:base, ts("You have reached our daily reporting limit. To keep our
                          volunteers from being overwhelmed, please do not seek
                          out violations to report, but only report violations you
                          encounter during your normal browsing."))
  end

  private

  def zoho_enabled?
    %w[staging production].include?(Rails.env)
  end
end
