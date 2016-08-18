class User < ActiveRecord::Base

  devise :cas_authenticatable
  has_one :user_setting, dependent: :destroy
  accepts_nested_attributes_for :user_setting

  enum user_group: { subscriber: 'subscriber', trialist: 'trialist', trial_registrant: 'trial_registrant', email_registrant: 'email_registrant', test: 'test' }

  enum delivery_type: { standard: 'standard', instant: 'instant', full: 'full', full_instant: 'full_instant' }

  validates :name, length: { maximum: 255 }
  validates_uniqueness_of :email
  validates :email, presence: true, email: true

  scope :subscribers, -> { where(user_group: :subscriber) }
  scope :trialists,   -> { where(user_group: :trialist) }
  scope :in_sso,      -> { where(user_group: [:subscriber, :trialist]) }

  before_create :set_default_params
  after_commit :update_mailgun_recipient, on: [:create, :update]
  after_destroy :remove_mailgun_recipient

  def self.find_all_to_notify(user_groups)
    user_main_groups = user_groups.map {|user_group| user_group.gsub('_full', '').gsub('_full_instant', '').gsub('_instant', ''); }
    users = self.joins('INNER JOIN user_settings ON (user_settings.user_id = users.id AND (user_settings.email_alerts=true OR user_settings.email_alerts is NULL))')
                .where(user_group: user_main_groups)
    emails = users.map{|user| user.email if user_groups.include? "#{user.user_group}_#{user.delivery_type}" or (user_groups.include? "#{user.user_group}" and user.delivery_type.to_s.gsub('standard', '').blank?) or ['trial_registrant', 'email_registrant'].include? user.user_group }.compact
    return emails
  end

  def track_registration
    self.increment(:sign_up_count)
    self.sign_up_at = Time.zone.now
  end

  def cas_extra_attributes=(extra_attributes)
    extra_attributes.each do |name, value|
      case name.to_sym
        when :fullname
          self.fullname = value
        when :email
          self.email = value
      end
    end
  end

  def user_group=(value)
    self.user_group_changed_at = Time.zone.now
    self.previous_user_group = self.user_group_was
    super(value)
  end

  def delivery_type=(value)
    self.previous_delivery_type = self.delivery_type_was
    super(value)
  end

  def self.user_groups_instant
    return ['subscriber_instant', 'subscriber_full_instant', 'trialist_instant', 'trialist_full_instant']
  end

  def settings
    self.user_setting ||= UserSetting.create(UserSetting::DEFAULT)
  end

  def cookies_enabled?
    settings.cookie
  end


  protected

  def set_default_params
    self.user_group ||= :trialist
    self.user_group_changed_at ||= Time.zone.now
    self.sign_up_at = Time.zone.now
    self.user_setting ||= UserSetting.create(UserSetting::DEFAULT)
    self.delivery_type ||= "standard"
    self.previous_delivery_type ||= "standard"
  end

  def remove_mailgun_recipient
    MailgunService.new.remove_member(self, self.user_group, self.delivery_type)
  end

  def update_mailgun_recipient
    if self.user_setting.email_alerts
      MailgunService.new.move_member(self)
    else
      remove_mailgun_recipient
    end
  end

end
