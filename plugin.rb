# frozen_string_literal: true

# name: discourse-add-chat-user
# about: Automatically adds a supervisor user to every direct message conversation
# version: 0.1
# authors: kuma
# url: https://github.com/kuma/discourse-add-chat-user

enabled_site_setting :add_chat_user_enabled

after_initialize do
  # Only proceed if the Chat plugin is loaded
  next unless defined?(::Chat)

  module ::DiscourseAddChatUser
    PLUGIN_NAME = "discourse-add-chat-user"

    def self.enabled?
      SiteSetting.add_chat_user_enabled
    end

    def self.supervisor_username
      SiteSetting.add_chat_user_supervisor_username.presence
    end

    def self.supervisor_user
      return nil unless enabled?
      username = supervisor_username
      return nil if username.blank?
      User.find_by(username: username)
    end

    def self.supervisor_user_id
      return nil unless enabled?
      configured_supervisor_user_id
    end

    def self.configured_supervisor_user_id
      username = supervisor_username
      return nil if username.blank?
      User.where(username: username).pick(:id)
    end

    def self.restrict_dm_to_staff?
      SiteSetting.add_chat_user_restrict_dm_to_staff
    end

    # Core logic: add supervisor to a DM channel
    def self.add_supervisor_to_channel(channel)
      return unless enabled?
      return unless channel&.direct_message_channel?

      supervisor = supervisor_user
      return if supervisor.nil?

      direct_message = channel.chatable
      return if direct_message.nil?

      # Skip if supervisor is already in the DM participants list.
      return if direct_message.direct_message_users.exists?(user_id: supervisor.id)

      now = Time.zone.now
      always_level = ::Chat::UserChatChannelMembership::NOTIFICATION_LEVELS[:always]

      # Step 1: Grant access via direct_message_users
      ::Chat::DirectMessageUser.insert_all(
        [{
          user_id: supervisor.id,
          direct_message_channel_id: direct_message.id,
          created_at: now,
          updated_at: now,
        }],
        unique_by: %i[direct_message_channel_id user_id],
      )

      # Step 2: Create channel membership
      ::Chat::UserChatChannelMembership.insert_all(
        [{
          user_id: supervisor.id,
          chat_channel_id: channel.id,
          muted: false,
          following: true,
          notification_level: always_level,
          created_at: now,
          updated_at: now,
        }],
        unique_by: %i[user_id chat_channel_id],
      )

      # Step 3: Refresh user count
      channel.update!(
        user_count: ::Chat::ChannelMembershipsQuery.count(channel),
        user_count_stale: false,
      )

      Rails.logger.info(
        "[#{PLUGIN_NAME}] Added supervisor '#{supervisor.username}' to channel ##{channel.id}"
      )
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Hook 0: Restrict non-staff users to only DM staff members
  # Uses the official modifier extension point in
  # Chat::CreateDirectMessageChannel#can_create_direct_message
  #
  # When enabled, non-staff users can only create DMs with users
  # who have admin or moderator roles. Staff users are unrestricted.
  # ──────────────────────────────────────────────────────────────
  register_modifier(:chat_can_create_direct_message_channel) do |actor_user, target_users|
    if ::DiscourseAddChatUser.restrict_dm_to_staff? && !actor_user.staff?
      # Exclude the actor themselves from the staff check —
      # target_users includes the actor (added by the service).
      other_targets = target_users.reject { |u| u.id == actor_user.id }
      other_targets.all?(&:staff?)
    else
      true
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Hook 1: Inject supervisor when a new DM channel is created
  # Target: Chat::CreateDirectMessageChannel#create_memberships
  # ──────────────────────────────────────────────────────────────
  module ::DiscourseAddChatUser::CreateDmChannelExtension
    def create_memberships(channel:, target_users:, guardian:)
      super
      ::DiscourseAddChatUser.add_supervisor_to_channel(channel)
    end
  end
  ::Chat::CreateDirectMessageChannel.prepend(
    ::DiscourseAddChatUser::CreateDmChannelExtension,
  )

  # ──────────────────────────────────────────────────────────────
  # Hook 2: Ensure supervisor exists when users are added to
  #         existing group DMs via AddUsersToChannel
  # ──────────────────────────────────────────────────────────────
  module ::DiscourseAddChatUser::AddUsersExtension
    def create_memberships(channel:, target_users:)
      super
      ::DiscourseAddChatUser.add_supervisor_to_channel(channel)
    end
  end
  ::Chat::AddUsersToChannel.prepend(
    ::DiscourseAddChatUser::AddUsersExtension,
  )

  # ──────────────────────────────────────────────────────────────
  # Hook 3: Patch DirectMessage.for_user_ids to exclude supervisor
  #         from array matching, preventing duplicate DM channels
  #
  # Without this patch, a DM between [A, B] would have users
  # [A, B, Supervisor] after the supervisor is added. The next
  # lookup for [A, B] would fail to match [A, B, Supervisor],
  # causing a duplicate channel to be created.
  #
  # The FILTER clause excludes the supervisor from ARRAY_AGG so
  # the comparison remains [A, B] = [A, B].
  # ──────────────────────────────────────────────────────────────
  module ::DiscourseAddChatUser::ForUserIdsPatch
    def for_user_ids(user_ids, group: false)
      # Keep DM lookup stable even when plugin is disabled.
      # Existing channels may already include supervisor in direct_message_users.
      supervisor_id = ::DiscourseAddChatUser.configured_supervisor_user_id

      # Fall through to original when:
      # - Supervisor not configured
      # - Supervisor is a natural participant in this lookup
      if supervisor_id.nil? || user_ids.include?(supervisor_id)
        return super
      end

      joins(:users)
        .where(group: group)
        .group("direct_message_channels.id")
        .having(
          "ARRAY[?] = ARRAY_AGG(users.id ORDER BY users.id) FILTER (WHERE users.id != ?)",
          user_ids.sort,
          supervisor_id,
        )
        .first
    end
  end
  ::Chat::DirectMessage.singleton_class.prepend(
    ::DiscourseAddChatUser::ForUserIdsPatch,
  )
end
