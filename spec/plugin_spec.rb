# frozen_string_literal: true

RSpec.describe "DiscourseAddChatUser integration" do
  fab!(:current_user) { Fabricate(:user, username: "actor", refresh_auto_groups: true) }
  fab!(:target_user) { Fabricate(:user, username: "target") }
  fab!(:supervisor) { Fabricate(:user, username: "supervisor") }

  let(:guardian) { Guardian.new(current_user) }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.add_chat_user_supervisor_username = supervisor.username
  end

  def create_dm
    Chat::CreateDirectMessageChannel.call(
      guardian: guardian,
      params: {
        target_usernames: [target_user.username],
      },
    )
  end

  it "adds supervisor into a newly created DM when enabled" do
    SiteSetting.add_chat_user_enabled = true

    result = create_dm

    expect(result).to be_a_success
    expect(result.channel.chatable.user_ids).to include(supervisor.id)
    expect(result.channel.user_chat_channel_memberships.exists?(user_id: supervisor.id)).to eq(true)
  end

  it "reuses existing DM after plugin is disabled" do
    SiteSetting.add_chat_user_enabled = true
    first = create_dm

    expect(first).to be_a_success
    expect(first.channel.chatable.user_ids).to include(supervisor.id)

    existing_channel_id = first.channel.id

    SiteSetting.add_chat_user_enabled = false

    second = nil
    expect { second = create_dm }.not_to change(Chat::DirectMessage, :count)

    expect(second).to be_a_success
    expect(second.channel.id).to eq(existing_channel_id)
  end

  it "falls back to original lookup when supervisor is a natural participant" do
    SiteSetting.add_chat_user_enabled = true

    dm = Chat::DirectMessage.create!(user_ids: [current_user.id, supervisor.id], group: false)

    found = Chat::DirectMessage.for_user_ids([current_user.id, supervisor.id], group: false)

    expect(found.id).to eq(dm.id)
  end
end
