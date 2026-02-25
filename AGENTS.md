# Repository Guidelines

## Project Structure & Module Organization
This repository is a minimal Discourse plugin focused on DM participant injection.

- `plugin.rb`: Main plugin entrypoint and runtime logic (`after_initialize`, Chat hooks, and DM lookup patch).
- `config/settings.yml`: Site settings exposed in Discourse Admin (`add_chat_user_*` keys).
- `config/locales/`: Reserved for i18n strings (currently empty).
- `README.md`: High-level behavior summary.
- `discourse/` and `discourse-add-chat-user/`: Reference-only workspace artifacts; do not add feature code there.

Keep new production code in `plugin.rb` or split into plugin-local Ruby files only when complexity justifies it.

## Build, Test, and Development Commands
This plugin does not build standalone; run it through a local Discourse checkout.

- `ln -s "$PWD" ../discourse/plugins/discourse-add-chat-user`: Link plugin into Discourse.
- `cd ../discourse && bin/rails server`: Start Discourse with this plugin loaded.
- `cd ../discourse && bundle exec rspec plugins/discourse-add-chat-user/spec`: Run plugin specs (when `spec/` exists).
- `cd ../discourse && bin/rails c`: Validate behavior quickly in Rails console.

## Coding Style & Naming Conventions
- Language: Ruby (Discourse plugin conventions).
- Indentation: 2 spaces, no tabs.
- Naming: `snake_case` for methods/settings, `CamelCase` for modules/classes.
- Prefix plugin-owned constants/modules with `DiscourseAddChatUser` to avoid collisions.
- Prefer small, composable methods and guard clauses; keep hook wrappers thin and delegate logic to shared helpers.

## Testing Guidelines
Use RSpec via Discourse’s test harness.

- Put tests under `spec/` (for example, `spec/services/add_supervisor_to_channel_spec.rb`).
- Cover both success path and safety guards: plugin disabled, missing supervisor, and duplicate-DM prevention.
- For behavior changes, include at least one regression spec for `Chat::DirectMessage.for_user_ids` matching.

## Commit & Pull Request Guidelines
Current history is minimal (`Initial commit`), so follow concise, imperative commit subjects in English.

- Suggested format: `<area>: <imperative summary>` (example: `chat: exclude supervisor in DM lookup`).
- PRs should include: purpose, behavior impact, test evidence (`rspec` output or manual validation steps), and related issue link.
- Add screenshots only when admin UI/settings presentation changes.
